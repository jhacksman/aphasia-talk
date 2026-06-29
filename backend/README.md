# Aphasia Talk — Backend

FastAPI service that orchestrates sentence generation (vLLM), speech-to-text
(whisper.cpp), and bookmark/word storage (SQLite). See [`../SPEC.md`](../SPEC.md)
for the full design.

## Run locally (no GPU)

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8080
```

`MOCK_INFERENCE` defaults to `true`, so `/generate`, `/vision`, and
`/transcribe` return plausible fabricated data — the whole UI works without a
DGX Spark. Open http://127.0.0.1:8080/ for the bundled web frontend.

## Tests

```bash
pip install -r requirements-dev.txt
python -m pytest -q
```

The suite runs in mock-inference mode (no GPU): it covers routing, response
shapes, SQLite persistence, bookmark pinning, profile composition, and the
real-mode JSON-parsing resilience guards (via a fake vLLM client). It does
**not** verify real model output — that requires the Spark stack. CI runs
this on every push and PR.

## Run on the DGX Spark (real models)

Set `MOCK_INFERENCE=false` and point `VLLM_URL` / `WHISPER_URL` at the running
inference services (see [`../docker-compose.yml`](../docker-compose.yml)).

## Configuration

Environment variables (see [`.env.example`](.env.example)):

| Variable | Default | Purpose |
|----------|---------|---------|
| `MOCK_INFERENCE` | `true` | Fabricate output instead of calling models |
| `VLLM_URL` | `http://vllm:8000` | vLLM OpenAI-compatible endpoint |
| `VLLM_MODEL` | `Qwen/Qwen3.6-35B-A3B-FP8` | Model name passed to vLLM |
| `WHISPER_URL` | `http://whisper:8001` | whisper.cpp server endpoint |
| `DATABASE_PATH` | `app/data/aphasia_talk.db` | SQLite file location |

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Liveness + whether mock mode is on |
| GET | `/words` | Word grid (categories, icons, stable positions) |
| POST | `/generate` | Sentences + related words for a tapped word |
| POST | `/vision` | Identify an object in a photo, then generate |
| POST | `/transcribe` | Speech-to-text for dictation |
| GET | `/bookmarks` | List saved sentences |
| POST | `/bookmarks` | Save a sentence |
| DELETE | `/bookmarks/{id}` | Remove a saved sentence |
| POST | `/speak-log` | Record that a sentence was spoken (usage weighting) |

Saved sentences for a word are always pinned to the top of `/generate`
results and marked `bookmarked: true`.
