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
  backend/             # FastAPI Python backend
  frontend/            # Flutter tablet app
  docker-compose.yml   # DGX Spark deployment (vLLM + whisper.cpp + backend)
```

## Quick Start

See [SPEC.md](SPEC.md) for the complete technical specification, API design, UI layout, and deployment guide.

## License

MIT
