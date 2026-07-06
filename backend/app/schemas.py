"""Request and response models for the public API."""
from __future__ import annotations

from pydantic import BaseModel, Field


class Sentence(BaseModel):
    text: str
    bookmarked: bool = False


class GenerateRequest(BaseModel):
    word: str = Field(..., min_length=1)
    category: str | None = None
    bookmarked_sentences: list[str] = Field(default_factory=list)
    history_context: list[str] = Field(default_factory=list)


class GenerateResponse(BaseModel):
    sentences: list[Sentence]
    related_words: list[str]


class VisionResponse(BaseModel):
    identified_object: str
    confidence: float
    sentences: list[Sentence]
    related_words: list[str]


class TranscribeResponse(BaseModel):
    text: str
    confidence: float


class AskResponse(BaseModel):
    # text == "" means the audio yielded nothing usable (silence, filtered
    # hallucination); the client shows a calm "try again" to the caregiver.
    text: str
    turn_id: int | None = None


class RespondRequest(BaseModel):
    question: str = Field(..., min_length=1)


class ConversationTurn(BaseModel):
    id: int
    role: str  # 'heard' | 'spoken'
    text: str
    created_at: str


class ConversationResponse(BaseModel):
    turns: list[ConversationTurn]


class Bookmark(BaseModel):
    id: int
    text: str
    word: str
    category: str | None = None
    created_at: str


class BookmarkCreate(BaseModel):
    text: str = Field(..., min_length=1)
    word: str = Field(..., min_length=1)
    category: str | None = None


class BookmarkList(BaseModel):
    bookmarks: list[Bookmark]


class WordTile(BaseModel):
    text: str
    icon: str
    position: list[int]


class Category(BaseModel):
    name: str
    color: str
    words: list[WordTile]


class WordsResponse(BaseModel):
    categories: list[Category]


class ProfileModel(BaseModel):
    name: str | None = None
    birth_year: int | None = Field(default=None, ge=1900, le=2030)
    region: str | None = None
    idiolect_notes: str | None = None


class ProfileResponse(ProfileModel):
    # Echo back the composed persona section so a caregiver can see the effect.
    formative_decade: int | None = None
    system_prompt_preview: str
