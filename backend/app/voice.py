"""Cloned-voice support: reference storage and TTS proxying.

The caregiver uploads a recording of her voice (mp3/wav) from the tablet.
We normalize it to 16 kHz mono WAV (ffmpeg), transcribe it with the whisper
service already on the box (the clone needs reference text, and nobody
should have to type out an old voicemail), and store both under
settings.voice_dir — a volume shared with the Qwen3-TTS sidecar (spark/tts).

Speech requests are proxied to the sidecar. In mock mode /tts returns a
short generated tone so the whole app flow is exercisable without a GPU.
"""
from __future__ import annotations

import io
import json
import math
import shutil
import struct
import subprocess
import wave
from pathlib import Path

from . import db, whisper
from .config import settings

REFERENCE_WAV = "reference.wav"
_META_KEY = "voice_reference_meta"

ALLOWED_SUFFIXES = {".wav", ".mp3"}
MAX_UPLOAD_BYTES = 50 * 1024 * 1024  # generous; voicemails and clips are small


class VoiceError(Exception):
    """User-visible upload/processing failure with a plain message."""

    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.message = message
        self.status = status


def _voice_dir() -> Path:
    d = Path(settings.voice_dir)
    d.mkdir(parents=True, exist_ok=True)
    return d


def reference_path() -> Path:
    return _voice_dir() / REFERENCE_WAV


def enabled() -> bool:
    """Cloned voice is disabled entirely when TTS_URL is empty (config
    contract) — the tablet then only offers the built-in voice."""
    return bool(settings.tts_url.strip())


def get_status() -> dict:
    """What the Settings sheet shows: is a cloned voice ready to use?"""
    meta_raw = db.get_setting(_META_KEY)
    meta = json.loads(meta_raw) if meta_raw else None
    has_reference = enabled() and reference_path().is_file() and meta is not None
    return {
        "cloned_available": has_reference,
        "original_filename": (meta or {}).get("original_filename"),
        "transcript": (meta or {}).get("transcript"),
        "duration_seconds": (meta or {}).get("duration_seconds"),
    }


async def store_reference(data: bytes, filename: str, transcript: str | None) -> dict:
    """Normalize an uploaded recording, transcribe it if needed, persist both."""
    if not data:
        raise VoiceError("The uploaded file is empty.")
    if len(data) > MAX_UPLOAD_BYTES:
        raise VoiceError("That recording is too large — please use a clip under ~5 minutes.")
    suffix = Path(filename or "").suffix.lower()
    if suffix not in ALLOWED_SUFFIXES:
        raise VoiceError("Please upload a .wav or .mp3 recording.")

    wav_bytes = _normalize_to_wav(data, suffix)
    duration = _wav_duration_seconds(wav_bytes)
    if duration < 3.0:
        raise VoiceError(
            "That clip is too short — the voice needs at least a few seconds of speech."
        )

    text = (transcript or "").strip()
    if not text:
        text, _confidence = await whisper.transcribe(wav_bytes, "wav")
        text = text.strip()
        if not text:
            raise VoiceError(
                "Couldn't hear any speech in that recording. "
                "Try a clearer clip, or enter the spoken words by hand."
            )

    reference_path().write_bytes(wav_bytes)
    meta = {
        "original_filename": filename,
        "transcript": text,
        "duration_seconds": round(duration, 1),
    }
    db.set_setting(_META_KEY, json.dumps(meta))
    return get_status()


# Synthesized WAVs keyed by (text, reference mtime): her bookmarked/repeated
# sentences — the most-tapped by design — play instantly instead of paying
# GPU synthesis on every tap. Invalidates automatically on a new reference.
_wav_cache: dict[tuple[str, float], bytes] = {}
_WAV_CACHE_MAX = 128


async def synthesize(text: str) -> bytes:
    """Return WAV audio of `text` in the cloned voice."""
    if not enabled():
        raise VoiceError("The cloned voice is turned off on this server.", status=409)

    # Contract first: 409-without-reference must behave identically in mock
    # and real mode (the tablet's fallback depends on it). Mock replaces only
    # the sidecar call — the upload flow works in mock, so upload first.
    status = get_status()
    if not status["cloned_available"]:
        raise VoiceError("No voice recording has been uploaded yet.", status=409)

    if settings.mock_inference:
        return _mock_tone_wav()

    ref_mtime = reference_path().stat().st_mtime
    cache_key = (text, ref_mtime)
    cached = _wav_cache.get(cache_key)
    if cached is not None:
        return cached

    from .llm import get_client  # shared keep-alive client

    resp = await get_client().post(
        f"{settings.tts_url.rstrip('/')}/tts",
        json={
            "text": text,
            "ref_audio": str(reference_path()),
            "ref_text": status["transcript"],
        },
    )
    resp.raise_for_status()
    audio = resp.content
    if len(_wav_cache) >= _WAV_CACHE_MAX:
        _wav_cache.pop(next(iter(_wav_cache)))  # drop oldest inserted
    _wav_cache[cache_key] = audio
    return audio


# ── Audio helpers ────────────────────────────────────────────────────────────

def _normalize_to_wav(data: bytes, suffix: str) -> bytes:
    """Convert any accepted upload to 16 kHz mono PCM WAV.

    Uses ffmpeg when present (required for mp3, and fixes odd wav variants).
    Falls back to accepting already-valid WAV untouched when ffmpeg is absent
    (dev environments), so the flow is still testable.
    """
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        # ffmpeg must write to a real (seekable) file, NOT a pipe: with
        # pipe:1 it can't seek back to patch the RIFF sizes and leaves
        # 0xFFFFFFFF placeholders — wave then reports a ~37-hour duration,
        # silently disabling the too-short guard and storing broken headers.
        import tempfile

        with tempfile.TemporaryDirectory(prefix="aphasia-voice-") as tmp:
            src = Path(tmp) / f"upload{suffix}"
            dst = Path(tmp) / "normalized.wav"
            src.write_bytes(data)
            proc = subprocess.run(
                [ffmpeg, "-hide_banner", "-loglevel", "error",
                 "-i", str(src), "-ac", "1", "-ar", "16000",
                 "-f", "wav", "-y", str(dst)],
                capture_output=True,
            )
            if proc.returncode != 0 or not dst.is_file() or dst.stat().st_size == 0:
                raise VoiceError("Couldn't read that audio file — is it a valid recording?")
            return dst.read_bytes()

    if suffix == ".mp3":
        raise VoiceError(
            "This server can't convert mp3 (ffmpeg missing) — please upload a .wav.",
            status=422,
        )
    # Validate it's a readable WAV before storing as-is.
    try:
        with wave.open(io.BytesIO(data)) as w:
            w.getnframes()
    except (wave.Error, EOFError):
        raise VoiceError("Couldn't read that audio file — is it a valid .wav?")
    return data


def _wav_duration_seconds(wav_bytes: bytes) -> float:
    try:
        with wave.open(io.BytesIO(wav_bytes)) as w:
            rate = w.getframerate() or 1
            return w.getnframes() / rate
    except (wave.Error, EOFError):
        return 0.0


def _mock_tone_wav(seconds: float = 0.4, freq: float = 440.0) -> bytes:
    """A soft beep standing in for cloned speech in GPU-less dev."""
    rate = 16000
    n = int(rate * seconds)
    frames = b"".join(
        struct.pack("<h", int(0.25 * 32767 * math.sin(2 * math.pi * freq * i / rate)))
        for i in range(n)
    )
    buf = io.BytesIO()
    with wave.open(buf, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(frames)
    return buf.getvalue()
