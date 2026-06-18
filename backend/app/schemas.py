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
