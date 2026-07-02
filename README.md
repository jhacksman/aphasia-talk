# Aphasia Talk

Communication aid for a person with Alzheimer's and aphasia. Tablet app (iOS + Android) backed by local AI on an NVIDIA DGX Spark.

## How It Works

Mom taps a word button → AI generates sentences she might be trying to say → she taps one → tablet speaks it aloud.

**Three input modes:**
- **Word grid** — Categorized buttons (People, Needs, Feelings, Actions, Places). Tap a word, get sentences.
- **Microphone** — Speak a word, get sentences.
- **Camera** — Photograph an object, AI identifies it, get sentences.

**Sentences are user-curated** — Mom bookmarks the ones she likes. Bookmarks pin to the top next time. No AI auto-saving.

## Stack

| Component | Technology | Why |
|-----------|-----------|-----|
| Model | Qwen3.6-35B-A3B (35B/3B MoE, native vision+text) | Latest open weights, ~50 tok/s on Spark, deep knowledge for expressive output |
| Inference | vLLM (`cu130-nightly`) | Prefix caching → 0.12s TTFT (vs 2-4s Ollama) |
| Speech-to-text | whisper.cpp (Whisper Large v3 Turbo GGUF) | Real-time streaming, sub-500ms latency, ~1.5 GB |
| Backend | FastAPI (Python) | Orchestrates vLLM + whisper.cpp, serves REST API |
| Frontend | Flutter | Pixel-perfect motor-stable grids, offline TTS, iOS+Android |
| Hardware | NVIDIA DGX Spark (128 GB unified, SM121, 273 GB/s) | All inference local, no cloud |

## Project Structure

```
aphasia-talk/
  SPEC.md              # Full project specification (start here)
  backend/             # FastAPI backend (orchestrates vLLM + whisper.cpp + SQLite)
  mobile/              # Flutter tablet app — Android + iOS (the release target)
  frontend/            # Web frontend (functional prototype + interaction reference)
  docker-compose.yml   # DGX Spark deployment (vLLM + whisper.cpp + backend)
```

The Flutter app in `mobile/` is the release target for Android and iOS
(see [mobile/README.md](mobile/README.md) for build + store instructions).
The web frontend remains a quick way to exercise the backend from any browser.

## Quick Start — Web (no GPU required)

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8080
```

Open **http://127.0.0.1:8080/**. The backend defaults to `MOCK_INFERENCE=true`,
so tapping a word returns plausible fabricated sentences — the entire UI
(word grid, generation, bookmarking, speech, photo, dictation) works without a
DGX Spark. Flip `MOCK_INFERENCE=false` on the Spark to use the real models.

## Quick Start — Flutter Tablet App

```bash
cd mobile
flutter pub get
flutter run          # run on connected device / emulator
```

The Flutter app connects to the backend over LAN. Set the backend address
in Settings (gear icon).

**Build for tablet:** see [mobile/README.md](mobile/README.md) for signed
Android (APK/AAB) and iOS (TestFlight) release steps.

See [backend/README.md](backend/README.md) for the API reference and
[SPEC.md](SPEC.md) for the complete specification.

## License

MIT
