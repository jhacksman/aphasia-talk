"""Shared test fixtures.

Tests run against an isolated temporary SQLite database in mock-inference mode,
so they never touch the dev DB or require a GPU / vLLM / whisper.cpp.
"""
import os
import pathlib
import tempfile

# Must be set before importing app.config (settings are read at import time).
_TMP = pathlib.Path(tempfile.mkdtemp(prefix="aphasia-test-"))
os.environ["DATABASE_PATH"] = str(_TMP / "test.db")
os.environ["MOCK_INFERENCE"] = "true"

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture()
def client():
    # Fresh database per test for isolation; the lifespan handler re-seeds it.
    db_path = pathlib.Path(os.environ["DATABASE_PATH"])
    if db_path.exists():
        db_path.unlink()
    with TestClient(app) as c:
        yield c
