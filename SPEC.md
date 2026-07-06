# Aphasia Talk — Project Specification

## What This Is

A tablet communication aid for a person with aphasia (e.g. from Alzheimer's disease or stroke). The user taps large word buttons on a two-pane screen; the left pane shows a categorized word grid, the right pane shows AI-generated sentences using that word. They can tap a sentence to have the tablet speak it aloud, or tap another word to refine. Additional input modes: microphone (speak a word → transcribe → generate sentences) and camera (photograph an object → identify it → generate sentences). All inference runs locally on an NVIDIA DGX Spark. No cloud APIs.

---

## Hardware

- **Machine**: NVIDIA DGX Spark (desktop form factor)
- **SoC**: GB10 Grace Blackwell Superchip
- **Memory**: 128 GB unified LPDDR5x (shared CPU + GPU), 273 GB/s bandwidth
- **Compute**: SM121, 1 PFLOP FP4
- **CPU**: 20-core ARM (aarch64) — 10x Cortex-X925 + 10x Cortex-A725
- **Storage**: 4 TB NVMe
- **OS**: Ubuntu + CUDA 13.0, Driver 580.x
- **Network**: LAN connection to tablet (WiFi or Ethernet)

---

## Models

### Text + Vision: Qwen3.6-35B-A3B

| Property | Value |
|----------|-------|
| Full name | `Qwen/Qwen3.6-35B-A3B` (or `-FP8` variant) |
| Release | April 2026, Apache 2.0 |
| Architecture | MoE — 35B total parameters, 3B active per token |
| Multimodal | Native vision-language fusion (early fusion, not bolted-on adapter) |
| Quantization | FP8 (~35 GB resident) |
| DGX Spark speed | ~50 tok/s decode (benchmarked: ZengboJamesWang/dgx-spark-vllm-qwen3.6-35b-a3b-dflash) |
| TTFT | 0.12s with prefix caching (vs 2-4s without) |
| Context | 262,144 tokens native |
| Vision benchmarks | 92.0 RefCOCO, 50.8 ODInW13, outperforms Claude Sonnet 4.5 on spatial intelligence |
| Thinking mode | Supports `/think` and `/no_think` — use `/no_think` for sentence generation (speed), `/think` for complex reasoning if ever needed |
| Hugging Face | `Qwen/Qwen3.6-35B-A3B-FP8` |

**Why this model**: It's the latest open-weight MoE from Qwen (April 2026). 3B active parameters means decode speed is governed by bandwidth, not compute — hitting ~50 tok/s on Spark's 273 GB/s bus. Native multimodal means one model handles both text generation AND camera/vision with no separate pipeline. 35B total parameters means it draws on deep knowledge for generating expressive, profound sentences — not generic filler.

### Speech-to-Text: Whisper Large v3 Turbo (via whisper.cpp)

| Property | Value |
|----------|-------|
| Model | Whisper Large v3 Turbo |
| Format | GGUF (~1.5 GB) |
| Runtime | whisper.cpp with CUDA 13 (SM121 supported) |
| Platform | linux/arm64 Docker image exists |
| Streaming | Real-time with built-in VAD (Voice Activity Detection) |
| Latency | Sub-500ms first-segment |
| Interface | HTTP server (whisper.cpp `--server` mode) |

---

## Inference Engine: vLLM

| Property | Value |
|----------|-------|
| Image | `vllm/vllm-openai:cu130-nightly` |
| SM121 support | Yes (merged March 2026) |
| API | OpenAI-compatible (`/v1/chat/completions`, `/v1/images`) |
| Key feature | **Prefix caching** — reuses KV cache for constant system prompt across all requests |
| TTFT | 0.12s (cache hit) vs 2-4s (Ollama, no caching) |
| Decode | ~50 tok/s for Qwen3.6-35B-A3B FP8 |
| Concurrent | Yes (handles multiple requests, though single-user in practice) |

**Why vLLM over Ollama**: Ollama works on SM121 and is simpler to set up (`ollama pull`), but it lacks prefix caching. Every tap re-processes the full system prompt from scratch (2-4s TTFT). For someone with Alzheimer's who may lose focus in seconds, that latency is a dealbreaker. vLLM's prefix caching drops TTFT to 0.12s — feels instant. The 30% decode speed advantage (52 vs 40 tok/s on same model, ai-muninn benchmark) is a bonus. Trade-off: Docker + configuration vs one command. Worth it for 20x TTFT improvement.

**vLLM launch flags** (known gotchas for DGX Spark):
```bash
vllm serve Qwen/Qwen3.6-35B-A3B-FP8 \
  --host 0.0.0.0 \
  --port 8000 \
  --gpu-memory-utilization 0.85 \
  --max-model-len 131072 \
  --enable-prefix-caching \
  --reasoning-parser qwen3 \
  --kv-cache-dtype auto \
  --max-num-seqs 4 \
  --max-num-batched-tokens 4096
```

**DO NOT** use `--enable-chunked-prefill` — causes 9x throughput regression on SSM+MoE hybrid models on GB10.
**DO NOT** use `--kv-cache-dtype fp8` — causes output repetition loops on GB10.

---

## Memory Budget

| Component | Memory |
|-----------|--------|
| Qwen3.6-35B-A3B FP8 weights | ~35 GB |
| Whisper Large v3 Turbo GGUF | ~1.5 GB |
| vLLM KV cache + overhead | ~20 GB |
| whisper.cpp runtime | ~1 GB |
| OS + system | ~5 GB |
| **Total used** | **~63 GB** |
| **Remaining** | **~65 GB** |

---

## UI Design

The UI matches the reference mockup — a two-pane tablet layout:

### Layout (Landscape, primary orientation)

```
┌─────────────────────────────────────────────────────────────────┐
│  [Tap words or a sentence below...]          [X]  [🔊 Speak]   │
├──────────────────────────────┬──────────────────────────────────┤
│  ⊞ WORDS                     │  ⊞ SENTENCES                    │
│                              │                                  │
│  [People] [Needs] [Feelings] │  • I need help right now.       │
│  [Actions] [Places]          │  • I am thirsty.                │
│                              │  • I am hungry.                 │
│  ┌─────┐ ┌─────┐ ┌─────┐   │  • I am in pain.                │
│  │  👤 │ │  👥 │ │ 👨‍👩‍👧 │   │  • I need to rest.              │
│  │  I  │ │ you │ │family│   │  • I need the bathroom.         │
│  └─────┘ └─────┘ └─────┘   │  • I need my medicine.          │
│  ┌─────┐ ┌─────┐ ┌─────┐   │  • Please call my family.       │
│  │  🩺 │ │  🏥 │ │  🤝 │   │                                  │
│  │doctor│ │nurse│ │friend│   │                                  │
│  └─────┘ └─────┘ └─────┘   │                                  │
│                              │                                  │
├──────────────────────────────┴──────────────────────────────────┤
│       [🎤 Dictate]     [📷 Photo]     [⌨️ Keyboard]             │
└─────────────────────────────────────────────────────────────────┘
```

### Interaction Flow

1. **App opens** → Default category ("Needs") shown with common words. Sentences pane shows the most frequently bookmarked sentences (or a welcome state).

2. **Tap a word** (e.g., "thirsty") →
   - Right pane populates with AI-generated sentences: "I am thirsty.", "Can I have some water?", "I need something to drink.", etc.
   - Word grid may show related words: "water", "drink", "juice", "cold"
   - Bookmarked sentences for this word appear pinned at the top (marked with a star)

3. **Tap a sentence** →
   - Sentence appears in the top bar
   - Tablet speaks it aloud (TTS)
   - Option to bookmark it (star icon)

4. **Tap [Speak] button** → Speaks the currently selected sentence aloud again

5. **Tap [Dictate]** →
   - Microphone activates, whisper.cpp streams audio
   - Transcribed word(s) appear in top bar
   - Triggers sentence generation for that word
   - Basically the same as tapping a word, but input is voice

6. **Tap [Photo]** →
   - Camera opens
   - User photographs an object
   - Image sent to Qwen3.6-35B-A3B vision endpoint
   - Model identifies the object (e.g., "cup", "blanket", "remote")
   - Triggers sentence generation for that identified word

7. **Tap [Keyboard]** →
   - Simple on-screen keyboard appears
   - User types a word (for caregiver use, or if the user can manage)
   - Triggers sentence generation

### Design Rules (AAC Research)

- **Buttons never move** — Motor planning stability. Once a word is in a grid position, it stays there forever. The user builds muscle memory.
- **Touch targets**: Minimum 64dp x 64dp (larger is better; the reference shows ~100dp)
- **Contrast**: WCAG AAA (7:1 minimum for text, 4.5:1 for large text/icons)
- **Color coding**: Fitzgerald Key system — People (yellow), Actions (green), Descriptors (blue), Objects (orange), Places (purple), Social (pink)
- **No time pressure**: Nothing times out, nothing auto-dismisses
- **Visual verification**: The selected sentence is displayed in the top bar before being spoken — user confirms it's correct
- **Consistent layout**: Two-pane stays two-pane. No mode switches, no drawer navigation, no nested screens (except camera/keyboard overlays)

---

## Backend API (FastAPI)

Base URL: `http://<dgx-spark-ip>:8080`

### `POST /generate`

Generate sentences and related words for a given input word.

```json
// Request
{
  "word": "thirsty",
  "category": "needs",
  "bookmarked_sentences": ["I am thirsty.", "Can I have water?"],
  "history_context": ["water", "drink", "hungry"]
}

// Response
{
  "sentences": [
    {"text": "I am thirsty.", "bookmarked": true},
    {"text": "Can I have some water please?", "bookmarked": false},
    {"text": "I need something to drink.", "bookmarked": false},
    {"text": "My throat is dry.", "bookmarked": false},
    {"text": "Could you bring me a glass of water?", "bookmarked": false},
    {"text": "I want juice.", "bookmarked": false},
    {"text": "I haven't had anything to drink.", "bookmarked": false},
    {"text": "Please get me water.", "bookmarked": true}
  ],
  "related_words": ["water", "drink", "juice", "cold", "ice", "cup"]
}
```

### `POST /vision`

Identify an object from a photo and generate sentences.

```json
// Request (multipart/form-data)
{
  "image": <binary image data>
}

// Response
{
  "identified_object": "television remote",
  "confidence": 0.94,
  "sentences": [
    {"text": "I want to watch TV.", "bookmarked": false},
    {"text": "Can you change the channel?", "bookmarked": false},
    {"text": "Please turn on the television.", "bookmarked": false}
  ],
  "related_words": ["TV", "watch", "channel", "volume", "show"]
}
```

### `POST /transcribe`

Transcribe audio from the microphone.

```json
// Request (multipart/form-data or WebSocket for streaming)
{
  "audio": <binary audio data>,
  "format": "wav"
}

// Response
{
  "text": "thirsty",
  "confidence": 0.91
}
```

Then the client calls `/generate` with the transcribed word.

### `GET /bookmarks`

Get all bookmarked sentences.

```json
// Response
{
  "bookmarks": [
    {"id": 1, "text": "I am thirsty.", "word": "thirsty", "created_at": "2026-06-15T10:30:00Z"},
    {"id": 2, "text": "I need the bathroom.", "word": "bathroom", "created_at": "2026-06-14T08:15:00Z"}
  ]
}
```

### `POST /bookmarks`

Save a sentence as a bookmark.

```json
// Request
{
  "text": "I am thirsty.",
  "word": "thirsty"
}
```

### `DELETE /bookmarks/{id}`

Remove a bookmark.

### `GET /words`

Get the word grid configuration (categories + words + positions).

```json
// Response
{
  "categories": [
    {
      "name": "People",
      "color": "#F5D63D",
      "words": [
        {"text": "I", "icon": "person", "position": [0, 0]},
        {"text": "you", "icon": "people", "position": [0, 1]},
        {"text": "family", "icon": "family", "position": [0, 2]},
        {"text": "doctor", "icon": "medical", "position": [1, 0]},
        {"text": "nurse", "icon": "nurse", "position": [1, 1]},
        {"text": "friend", "icon": "handshake", "position": [1, 2]}
      ]
    },
    {
      "name": "Needs",
      "color": "#4CAF50",
      "words": [
        {"text": "water", "icon": "water_drop", "position": [0, 0]},
        {"text": "food", "icon": "restaurant", "position": [0, 1]},
        {"text": "bathroom", "icon": "wc", "position": [0, 2]},
        {"text": "medicine", "icon": "medication", "position": [1, 0]},
        {"text": "rest", "icon": "bed", "position": [1, 1]},
        {"text": "help", "icon": "help", "position": [1, 2]}
      ]
    }
  ]
}
```

---

## System Prompt (for Qwen3.6-35B-A3B)

This is the constant system prompt that gets prefix-cached by vLLM:

```
You are a communication assistant for a person with aphasia (difficulty producing language) caused by Alzheimer's disease. Your job is to generate clear, natural sentences that express what they might be trying to say.

Rules:
- Generate 6-8 sentences per word, ranging from simple needs to more expressive/emotional thoughts
- Sentences should be first-person ("I..." or "Can you..." or "Please...")
- Mix practical sentences ("I need water") with deeper/emotional ones ("I miss how things used to be")
- Keep sentences short (under 15 words) — they will be spoken aloud by TTS
- If the user has bookmarked sentences for this word, those preferences indicate their style and needs — generate similar sentences
- Also suggest 4-6 related words that they might want to tap next
- Never generate anything condescending, childish, or patronizing — the user is an adult with full comprehension, they just can't produce the words themselves
- Output valid JSON only: {"sentences": [...], "related_words": [...]}
```

---

## Frontend: Flutter

### Why Flutter (not React Native / Expo)

- **Pixel-perfect rendering**: Custom Paint + Skia means buttons render identically on every device — critical for motor planning stability (buttons at exact same pixel position always)
- **Proven in AAC**: SproutAAC (production AAC app, 2026) built with Flutter
- **Offline TTS**: `flutter_tts` plugin provides native TTS without network — critical for a communication aid
- **Single codebase**: iOS + Android tablets from one Dart codebase
- **Performance**: Compiled to native ARM — no JS bridge overhead

### Key Packages

- `flutter_tts` — Text-to-speech (offline, system voices)
- `camera` — Camera access for photo input
- `record` or `flutter_sound` — Microphone recording
- `http` or `dio` — REST API calls to FastAPI backend
- `sqflite` — Local cache of bookmarks (synced to backend)
- `provider` or `riverpod` — State management

### App Structure

```
lib/
  main.dart
  app.dart
  models/
    word.dart
    sentence.dart
    category.dart
    bookmark.dart
  screens/
    home_screen.dart         # The two-pane main screen
    camera_screen.dart       # Camera overlay
    keyboard_screen.dart     # Typing overlay
  widgets/
    word_grid.dart           # Left pane — category tabs + word buttons
    word_button.dart         # Single large word button
    sentence_list.dart       # Right pane — generated sentences
    sentence_tile.dart       # Single sentence row
    input_bar.dart           # Bottom bar (Dictate, Photo, Keyboard)
    top_bar.dart             # Top bar (selected sentence + Speak)
  services/
    api_service.dart         # HTTP calls to FastAPI
    tts_service.dart         # Text-to-speech wrapper
    audio_service.dart       # Microphone recording
    bookmark_service.dart    # Local + remote bookmark management
  theme/
    app_theme.dart           # Colors, sizes, contrast
    fitzgerald_colors.dart   # Fitzgerald Key color system
```

---

## Data Storage

### On DGX Spark (SQLite via FastAPI)

- **bookmarks** table: `id`, `text`, `word`, `category`, `created_at`
- **word_config** table: `word`, `category`, `icon`, `position_row`, `position_col` (never changes once set — motor stability)
- **usage_log** table: `id`, `word`, `sentence_text`, `action` (tapped/spoken/bookmarked), `timestamp` — used to weight future generations

### On Tablet (sqflite cache)

- Mirror of bookmarks for offline display
- Last-generated sentences cache (show something immediately on app open even if Spark is unreachable)

---

## Deployment

### DGX Spark Docker Compose

```yaml
services:
  vllm:
    image: vllm/vllm-openai:cu130-nightly
    runtime: nvidia
    ports:
      - "8000:8000"
    volumes:
      - /home/user/models:/models
    command: >
      vllm serve Qwen/Qwen3.6-35B-A3B-FP8
      --host 0.0.0.0
      --port 8000
      --gpu-memory-utilization 0.85
      --max-model-len 131072
      --enable-prefix-caching
      --reasoning-parser qwen3
      --max-num-seqs 4
      --max-num-batched-tokens 4096
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]

  whisper:
    image: whisper-cpp-server:sm121
    runtime: nvidia
    ports:
      - "8001:8001"
    volumes:
      - /home/user/models/whisper:/models
    command: >
      --model /models/ggml-large-v3-turbo.bin
      --port 8001
      --host 0.0.0.0

  backend:
    build: ./backend
    ports:
      - "8080:8080"
    environment:
      - VLLM_URL=http://vllm:8000
      - WHISPER_URL=http://whisper:8001
      - DATABASE_URL=sqlite:///data/aphasia_talk.db
    volumes:
      - ./data:/app/data
    depends_on:
      - vllm
      - whisper
```

### Tablet App

- Built with Flutter, distributed via:
  - **iOS**: TestFlight (family testing) → App Store if desired
  - **Android**: Direct APK install or Google Play internal testing
- Connects to DGX Spark backend over LAN (WiFi)
- Backend IP configured on first launch (simple settings screen)

---

## Word Categories (Initial Seed)

Based on AAC core vocabulary research (Banajee, Dicarlo & Stricklin, 2003; Boenisch & Soto, 2015):

| Category | Words |
|----------|-------|
| **People** | I, you, family, doctor, nurse, friend, Jack, he, she, they, someone |
| **Needs** | water, food, bathroom, medicine, rest, help, blanket, glasses, phone, wheelchair |
| **Feelings** | happy, sad, tired, pain, scared, confused, love, angry, cold, hot, lonely, good, bad |
| **Actions** | go, come, want, need, like, stop, more, eat, drink, sleep, sit, stand, look, listen, tell |
| **Places** | home, bed, bathroom, kitchen, outside, hospital, here, there, room, garden |
| **Time** | now, later, morning, night, today, yesterday, always, soon, wait |
| **Social** | hello, goodbye, thank you, sorry, please, yes, no, okay, maybe |

Words can be added/removed by a caregiver through a settings interface. **Positions never change once set** — only new words can be added to empty slots.

---

## Personalization (User-Curated)

- **No AI auto-saving** — the AI does not decide what to remember
- **Explicit bookmarking** — the user (or caregiver) taps a star icon on a sentence to save it
- **Bookmarked sentences pin to top** — next time that word is tapped, bookmarked sentences appear first (before AI-generated ones)
- **"My Sentences" screen** — dedicated view showing all bookmarks, grouped by word/category, for direct access without going through the word grid
- **Usage weighting** — the backend tracks which words and sentences are tapped most often, and includes this context in the generation prompt (so the AI generates sentences in the user's style, not generic ones)

---

## Non-Goals (Out of Scope)

- Multi-user support (this is for one person)
- Cloud deployment or remote access
- Training or fine-tuning models
- Complex conversation threading (this is one-shot sentence generation, not a chatbot)
- Automatic sentence saving without user action
- Dynamic button rearrangement based on frequency (violates motor stability)

---

## Success Criteria

1. **Latency**: Tap a word → sentences appear in under 1.5 seconds (TTFT 0.12s + ~50 tok/s for ~80 tokens ≈ 1.7s total for all 8 sentences)
2. **Quality**: Generated sentences are natural, first-person, varied in depth (practical + emotional), never condescending
3. **Stability**: Word buttons never move. App never crashes. Always responsive.
4. **Accessibility**: Readable at arm's length, usable with imprecise motor control, hearable via TTS
5. **Offline resilience**: If Spark is off, app shows cached bookmarks and last-generated sentences
