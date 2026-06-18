"""SQLite persistence for bookmarks, the word grid, and usage logging."""
from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from .config import settings
from .seed import CATEGORY_COLORS, SEED_WORDS


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


@contextmanager
def _connect() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(settings.database_path)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    """Create tables if needed and seed the word grid on first run."""
    Path(settings.database_path).parent.mkdir(parents=True, exist_ok=True)
    with _connect() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS bookmarks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text TEXT NOT NULL,
                word TEXT NOT NULL,
                category TEXT,
                created_at TEXT NOT NULL,
                UNIQUE(text, word)
            );

            CREATE TABLE IF NOT EXISTS word_config (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL,
                category TEXT NOT NULL,
                color TEXT NOT NULL,
                icon TEXT NOT NULL,
                position_row INTEGER NOT NULL,
                position_col INTEGER NOT NULL,
                UNIQUE(category, position_row, position_col)
            );

            CREATE TABLE IF NOT EXISTS usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT,
                sentence_text TEXT,
                action TEXT NOT NULL,
                timestamp TEXT NOT NULL
            );
            """
        )
        seeded = conn.execute("SELECT COUNT(*) AS n FROM word_config").fetchone()["n"]
        if seeded == 0:
            _seed_words(conn)


def _seed_words(conn: sqlite3.Connection) -> None:
    rows = []
    for category, words in SEED_WORDS.items():
        color = CATEGORY_COLORS.get(category, "#607D8B")
        for text, icon, row, col in words:
            rows.append((text, category, color, icon, row, col))
    conn.executemany(
        """INSERT INTO word_config (word, category, color, icon, position_row, position_col)
           VALUES (?, ?, ?, ?, ?, ?)""",
        rows,
    )


# ── Word grid ────────────────────────────────────────────────────────────────

def get_word_config() -> list[dict]:
    """Return categories with their words, ordered by stable grid position."""
    with _connect() as conn:
        rows = conn.execute(
            """SELECT word, category, color, icon, position_row, position_col
               FROM word_config
               ORDER BY category, position_row, position_col"""
        ).fetchall()

    by_category: dict[str, dict] = {}
    # Preserve the seed ordering of categories rather than alphabetical.
    for name in SEED_WORDS.keys():
        by_category[name] = {
            "name": name,
            "color": CATEGORY_COLORS.get(name, "#607D8B"),
            "words": [],
        }
    for r in rows:
        cat = by_category.setdefault(
            r["category"],
            {"name": r["category"], "color": r["color"], "words": []},
        )
        cat["words"].append(
            {
                "text": r["word"],
                "icon": r["icon"],
                "position": [r["position_row"], r["position_col"]],
            }
        )
    return [c for c in by_category.values() if c["words"]]


# ── Bookmarks ──────────────────────────────────────────────────────────────

def list_bookmarks() -> list[dict]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT id, text, word, category, created_at FROM bookmarks ORDER BY created_at DESC"
        ).fetchall()
    return [dict(r) for r in rows]


def bookmarked_texts_for_word(word: str) -> list[str]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT text FROM bookmarks WHERE word = ? ORDER BY created_at DESC",
            (word,),
        ).fetchall()
    return [r["text"] for r in rows]


def add_bookmark(text: str, word: str, category: str | None) -> dict:
    with _connect() as conn:
        cur = conn.execute(
            """INSERT INTO bookmarks (text, word, category, created_at)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(text, word) DO UPDATE SET category=excluded.category
               RETURNING id, text, word, category, created_at""",
            (text, word, category, _now_iso()),
        )
        row = cur.fetchone()
    return dict(row)


def delete_bookmark(bookmark_id: int) -> bool:
    with _connect() as conn:
        cur = conn.execute("DELETE FROM bookmarks WHERE id = ?", (bookmark_id,))
        return cur.rowcount > 0


# ── Usage logging ────────────────────────────────────────────────────────────

def log_usage(action: str, word: str | None = None, sentence_text: str | None = None) -> None:
    with _connect() as conn:
        conn.execute(
            "INSERT INTO usage_log (word, sentence_text, action, timestamp) VALUES (?, ?, ?, ?)",
            (word, sentence_text, action, _now_iso()),
        )


def top_words(limit: int = 6) -> list[str]:
    """Most-tapped words, used to bias generation toward the user's style."""
    with _connect() as conn:
        rows = conn.execute(
            """SELECT word, COUNT(*) AS n FROM usage_log
               WHERE word IS NOT NULL AND action = 'tapped'
               GROUP BY word ORDER BY n DESC LIMIT ?""",
            (limit,),
        ).fetchall()
    return [r["word"] for r in rows]
