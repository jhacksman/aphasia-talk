"""Runtime configuration, read from environment variables."""
from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_DATA_DIR = Path(__file__).resolve().parent / "data"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Upstream inference services.
    vllm_url: str = "http://vllm:8000"
    vllm_model: str = "Qwen/Qwen3.6-35B-A3B-FP8"
    whisper_url: str = "http://whisper:8001"

    # When true, the backend fabricates plausible sentences / transcriptions
    # instead of calling vLLM and whisper.cpp. Lets the API run with no GPU.
    mock_inference: bool = True

    # SQLite database location.
    database_path: str = str(_DATA_DIR / "aphasia_talk.db")

    # Generation tuning. The timeout must survive vLLM's first-inference
    # kernel autotune after a cold boot (~60s on GB10); the UI never shows
    # a timer to the user, so a long ceiling here costs nothing.
    request_timeout: float = 120.0
    max_sentences: int = 8

    # Conversation context (Ask mode). Prompts only see the last few turns
    # from the last few minutes — a question from this morning must not
    # color an afternoon reply. Retention bounds the table itself; the log
    # is a working buffer, not an archive.
    conversation_window_turns: int = 6
    conversation_window_minutes: float = 5.0
    conversation_retention_days: int = 7


settings = Settings()
