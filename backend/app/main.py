"""Aphasia Talk backend — FastAPI orchestration layer.

Serves the word grid, sentence generation (text + vision), transcription,
and bookmark storage described in SPEC.md. Designed for a single user on a
LAN; no auth, no multi-tenancy.
"""
from __future__ import annotations

import json
from contextlib import asynccontextmanager
from pathlib import Path

import httpx

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import db, llm, voice, whisper
from .config import settings
from .profile import Profile, compose_system_prompt, formative_decade
from .schemas import (
    Bookmark,
    BookmarkCreate,
    BookmarkList,
    GenerateRequest,
    GenerateResponse,
    ProfileModel,
    ProfileResponse,
    Sentence,
    TranscribeResponse,
    VisionResponse,
    WordsResponse,
)

_PROFILE_KEY = "linguistic_profile"

# The composed system prompt only changes when the profile is updated (rare,
# single-user). Cache it so /generate and /vision don't re-read SQLite and
# re-compose on every request — keeping the byte-stable prefix vLLM caches.
_prompt_cache: str | None = None


def _load_profile() -> Profile:
    raw = db.get_setting(_PROFILE_KEY)
    return Profile.from_dict(json.loads(raw)) if raw else Profile()


def _active_system_prompt() -> str:
    global _prompt_cache
    if _prompt_cache is None:
        _prompt_cache = compose_system_prompt(llm.BASE_SYSTEM_PROMPT, _load_profile())
    return _prompt_cache


def _invalidate_prompt_cache() -> None:
    global _prompt_cache
    _prompt_cache = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()
    # The DB may have been swapped/reseeded since the last lifecycle (tests,
    # restores) — never serve a persona composed from the previous database.
    _invalidate_prompt_cache()
    yield
    await llm.aclose()


app = FastAPI(title="Aphasia Talk", version="0.1.0", lifespan=lifespan)

# Tablet connects over LAN; allow any origin since there is no auth surface.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _mark_bookmarked(texts: list[str], bookmarked: set[str]) -> list[Sentence]:
    return [Sentence(text=t, bookmarked=t in bookmarked) for t in texts]


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "mock_inference": settings.mock_inference}


@app.get("/words", response_model=WordsResponse)
async def get_words() -> WordsResponse:
    return WordsResponse(categories=db.get_word_config())


@app.post("/generate", response_model=GenerateResponse)
async def generate(req: GenerateRequest) -> GenerateResponse:
    db.log_usage(action="tapped", word=req.word)

    # Saved sentences for this word are authoritative — always pin them on top.
    saved = db.bookmarked_texts_for_word(req.word)
    bookmarked_set = set(saved) | set(req.bookmarked_sentences)
    history = req.history_context or db.top_words()

    texts, related = await llm.generate_sentences(
        word=req.word,
        category=req.category,
        bookmarked=list(bookmarked_set),
        history=history,
        system_prompt=_active_system_prompt(),
    )
    return GenerateResponse(
        sentences=_mark_bookmarked(texts, bookmarked_set),
        related_words=related,
    )


@app.post("/vision", response_model=VisionResponse)
async def vision(image: UploadFile = File(...)) -> VisionResponse:
    data = await image.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image upload")
    obj, confidence, texts, related = await llm.generate_from_image(
        data, image.content_type or "image/jpeg", system_prompt=_active_system_prompt()
    )
    db.log_usage(action="tapped", word=obj)
    # Reflect any sentences the user already bookmarked for this object.
    bookmarked_set = set(db.bookmarked_texts_for_word(obj))
    return VisionResponse(
        identified_object=obj,
        confidence=confidence,
        sentences=_mark_bookmarked(texts, bookmarked_set),
        related_words=related,
    )


@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(
    audio: UploadFile = File(...), format: str = "wav"
) -> TranscribeResponse:
    data = await audio.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty audio upload")
    text, confidence = await whisper.transcribe(data, format)
    return TranscribeResponse(text=text, confidence=confidence)


@app.get("/bookmarks", response_model=BookmarkList)
async def get_bookmarks() -> BookmarkList:
    return BookmarkList(bookmarks=[Bookmark(**b) for b in db.list_bookmarks()])


@app.post("/bookmarks", response_model=Bookmark)
async def create_bookmark(req: BookmarkCreate) -> Bookmark:
    row = db.add_bookmark(req.text, req.word, req.category)
    db.log_usage(action="bookmarked", word=req.word, sentence_text=req.text)
    return Bookmark(**row)


@app.delete("/bookmarks/{bookmark_id}")
async def remove_bookmark(bookmark_id: int) -> dict:
    if not db.delete_bookmark(bookmark_id):
        raise HTTPException(status_code=404, detail="Bookmark not found")
    return {"deleted": bookmark_id}


@app.get("/profile", response_model=ProfileResponse)
async def get_profile() -> ProfileResponse:
    return _profile_response(_load_profile())


@app.put("/profile", response_model=ProfileResponse)
async def update_profile(req: ProfileModel) -> ProfileResponse:
    # Merge only the fields the client actually sent, so a partial update (e.g.
    # the UI form, which never sends idiolect_notes) doesn't wipe stored fields.
    merged = _load_profile().to_dict()
    merged.update(req.model_dump(exclude_unset=True))
    profile = Profile.from_dict(merged)
    db.set_setting(_PROFILE_KEY, json.dumps(profile.to_dict()))
    _invalidate_prompt_cache()
    return _profile_response(profile)


def _profile_response(profile: Profile) -> ProfileResponse:
    return ProfileResponse(
        **profile.to_dict(),
        formative_decade=formative_decade(profile.birth_year) if profile.birth_year else None,
        system_prompt_preview=compose_system_prompt(llm.BASE_SYSTEM_PROMPT, profile),
    )


@app.get("/voice")
async def voice_status() -> dict:
    """Cloned-voice state for the tablet's Settings sheet."""
    return voice.get_status()


@app.post("/voice/reference")
async def upload_voice_reference(
    audio: UploadFile = File(...),
    transcript: str | None = Form(default=None),
) -> dict:
    """Upload her voice recording (mp3/wav). Normalized, auto-transcribed
    via whisper when no transcript is given, and stored for the TTS clone."""
    data = await audio.read()
    try:
        return await voice.store_reference(data, audio.filename or "", transcript)
    except voice.VoiceError as e:
        raise HTTPException(status_code=e.status, detail=e.message)
    except httpx.HTTPError:
        # Auto-transcription needs the whisper service; say so honestly
        # instead of a raw 500 that reads as "bad recording".
        raise HTTPException(
            status_code=503,
            detail="The transcription service isn't answering — try again in a "
                   "minute, or type the spoken words yourself.",
        )


@app.post("/tts")
async def tts(payload: dict) -> Response:
    """Speak `text` in the cloned voice; returns WAV audio."""
    text = str(payload.get("text") or "").strip()
    if not text:
        raise HTTPException(status_code=422, detail="No text to speak")
    try:
        audio_bytes = await voice.synthesize(text)
    except voice.VoiceError as e:
        raise HTTPException(status_code=e.status, detail=e.message)
    except httpx.HTTPError:
        # Sidecar down/unreachable — tablet falls back to its system voice.
        raise HTTPException(status_code=503, detail="Voice service unavailable")
    return Response(content=audio_bytes, media_type="audio/wav")


@app.post("/speak-log")
async def speak_log(payload: dict) -> dict:
    """Record that a sentence was spoken aloud (for usage weighting)."""
    db.log_usage(
        action="spoken",
        word=payload.get("word"),
        sentence_text=payload.get("text"),
    )
    return {"logged": True}


# Serve the bundled web frontend at the root, if present. The Flutter app and
# any external host can still hit the API directly; this is a convenience so a
# fresh `docker compose up` yields a usable URL. Check both the repo layout
# (../frontend) and the container layout (/app/frontend).
_APP_DIR = Path(__file__).resolve().parent
for _candidate in (_APP_DIR.parent / "frontend", _APP_DIR.parent.parent / "frontend"):
    if _candidate.is_dir():
        app.mount("/", StaticFiles(directory=str(_candidate), html=True), name="frontend")
        break
