"""Qwen3-TTS voice-cloning server.

Tiny wrapper: loads the Base model once, then serves
POST /tts {"text", "ref_audio", "ref_text"} -> WAV bytes.

The reference WAV lives on the shared ./data volume, written by the backend
when the caregiver uploads a recording from the tablet. The voice prompt is
rebuilt only when the reference changes (mtime), then reused — cloning setup
is the slow part, synthesis itself is fast.
"""
from __future__ import annotations

import io
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

MODEL_NAME = os.environ.get("TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-Base")

app = FastAPI(title="aphasia-tts")

_model = None
_voice_prompt = None
_voice_key: tuple[str, float] | None = None


def _get_model():
    global _model
    if _model is None:
        # Import here so the container can start (and report health) while
        # weights are still downloading on first boot.
        from qwen_tts import Qwen3TTSModel

        _model = Qwen3TTSModel.from_pretrained(MODEL_NAME, device_map="cuda")
    return _model


class TtsRequest(BaseModel):
    text: str
    ref_audio: str
    ref_text: str


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "model": MODEL_NAME, "loaded": _model is not None}


@app.post("/tts")
def tts(req: TtsRequest) -> Response:
    global _voice_prompt, _voice_key

    ref = Path(req.ref_audio)
    if not ref.is_file():
        raise HTTPException(status_code=409, detail="Reference audio not found")

    model = _get_model()

    key = (str(ref), ref.stat().st_mtime)
    if _voice_key != key:
        _voice_prompt = model.create_voice_clone_prompt(
            ref_audio=str(ref), ref_text=req.ref_text
        )
        _voice_key = key

    wavs, sample_rate = model.generate_voice_clone(
        text=req.text, voice_clone_prompt=_voice_prompt
    )

    import soundfile as sf

    buf = io.BytesIO()
    sf.write(buf, wavs[0], sample_rate, format="WAV")
    return Response(content=buf.getvalue(), media_type="audio/wav")
