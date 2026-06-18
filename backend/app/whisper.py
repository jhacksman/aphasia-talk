"""Speech-to-text via a whisper.cpp HTTP server, with a mock fallback."""
from __future__ import annotations

import httpx

from .config import settings


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

    text = (payload.get("text") or "").strip()
    # whisper.cpp does not return a single confidence scalar; treat presence
    # of text as success and report a nominal high confidence.
    return text, 0.9 if text else 0.0
