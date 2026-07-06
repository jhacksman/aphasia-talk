"""Qwen3-TTS voice-cloning server.

Tiny wrapper: loads the Base model once, then serves
POST /tts {"text", "ref_audio", "ref_text"} -> WAV bytes.

The reference WAV lives on the shared ./data volume, written by the backend
when the caregiver uploads a recording from the tablet. The voice prompt is
rebuilt only when the reference changes (mtime), then reused — cloning setup
is the slow part, synthesis itself is fast.

The model starts loading in the background at startup (not on the first
tap), and a lock prevents two concurrent requests from double-loading onto
the GPU during that window.
"""
from __future__ import annotations

import io
import os
import threading
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

MODEL_NAME = os.environ.get("TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-Base")

_model = None
_model_lock = threading.Lock()
_voice_prompt = None
_voice_key: tuple[str, float] | None = None


def _get_model():
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:  # double-checked: one load, ever
                from qwen_tts import Qwen3TTSModel

                _model = Qwen3TTSModel.from_pretrained(MODEL_NAME, device_map="cuda")
    return _model


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Warm up in the background so the first tap after a reboot doesn't pay
    # the model load (which would time out the tablet and read as "broken").
    threading.Thread(target=_get_model, daemon=True).start()
    yield


app = FastAPI(title="aphasia-tts", lifespan=lifespan)


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
    # One lock serializes prompt building AND generation: sync endpoints run
    # in a threadpool, and neither torch inference nor the prompt cache is
    # thread-safe. Single user — serialization is correct, not a bottleneck.
    with _model_lock:
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
