"""Speech-to-text via a whisper.cpp HTTP server, with a mock fallback."""
from __future__ import annotations

import re

import httpx

from .config import settings

# Phrases whisper hallucinates on silence/noise (training-data artifacts from
# video captions). Matched against the WHOLE transcript, case/punctuation
# insensitive — a real question containing one of these can't be just this.
_SILENCE_HALLUCINATIONS = {
    "you",
    "bye",
    "thank you",
    "thanks for watching",
    "thank you for watching",
    "please subscribe",
    "subtitles by the amara org community",
    "subs by www zeoranger co uk",
    "www mooji org",
}


def clean_transcript(text: str) -> str:
    """Drop transcripts that are known silence hallucinations, else pass
    the text through trimmed. Returns "" for garbage."""
    trimmed = text.strip()
    normalized = re.sub(r"[^a-z0-9 ]+", " ", trimmed.lower())
    normalized = " ".join(normalized.split())
    if normalized in _SILENCE_HALLUCINATIONS:
        return ""
    return trimmed


async def transcribe(audio_bytes: bytes, fmt: str = "wav") -> tuple[str, float]:
    if settings.mock_inference:
        return "water", 0.92

    files = {"file": (f"audio.{fmt}", audio_bytes, f"audio/{fmt}")}
    data = {"response_format": "json", "temperature": "0.0"}
    async with httpx.AsyncClient(timeout=settings.request_timeout) as client:
        # whisper.cpp --server exposes an OpenAI-compatible /inference endpoint.
        resp = await client.post(
            f"{settings.whisper_url}/inference", files=files, data=data
        )
        resp.raise_for_status()
        payload = resp.json()

    text = clean_transcript(payload.get("text") or "")
    # whisper.cpp does not return a single confidence scalar; treat presence
    # of text as success and report a nominal high confidence.
    return text, 0.9 if text else 0.0
