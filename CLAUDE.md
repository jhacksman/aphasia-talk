# Aphasia Talk — Agent Briefing

You are working on a communication aid for one person: the owner's mother,
who has Alzheimer's with aphasia. She understands language fully but cannot
produce it. She taps a word → the local AI generates candidate sentences →
she taps one → the tablet speaks it. This is not a demo or a startup — it is
one family's daily tool. Reliability and calm beat features.

## Architecture (all local, no cloud)

```
tablet (Flutter app, mobile/)  ──LAN──▶  DGX Spark
web client (frontend/)         ──LAN──▶    ├─ backend  :8080  FastAPI (backend/)
                                           ├─ vLLM     :8000  LLM+vision (OpenAI-compatible)
                                           └─ whisper  :8001  speech-to-text
```

- `backend/` — FastAPI. Endpoints: /generate, /vision, /transcribe, /words,
  /bookmarks, /profile, /speak-log, /voice, /voice/reference, /tts, /health.
  SQLite for bookmarks/config. `MOCK_INFERENCE=true` fabricates output so
  everything runs GPU-less (mock /tts returns a beep).
- Voice: the tablet offers "Fast" (on-device system TTS, default) and "Her
  voice" (Qwen3-TTS *Base* clone served by spark/tts on :8002 — Base is the
  only variant that clones). Caregiver uploads a wav/mp3 from tablet
  Settings; backend normalizes (ffmpeg) + auto-transcribes it via whisper.
  Cloned mode always falls back to the system voice — speech never fails.
- `mobile/` — the release Flutter app (Android + iOS). The single app; a
  duplicate tree (mobile_app/) was removed deliberately — don't resurrect it.
- `frontend/` — single-file web client; quickest way to exercise the backend.
- `spark/` — bring-up kit for this machine: setup.sh (models), whisper image,
  smoke_test.sh. **Start with spark/README.md if you're on the Spark.**

## Invariants — do not break these

1. **Buttons never move.** Word grid positions are stored [row, col] and
   render in that order forever. Motor-planning stability is the point.
   Never reorder by usage/frequency.
2. **The system prompt stays byte-stable per profile.** vLLM prefix caching
   is what makes taps feel instant (~0.1s TTFT vs seconds). It's composed
   once per profile change and cached (backend/app/main.py). Don't add
   per-request dynamic content to the system prompt.
3. **No cloud, no auth, LAN-only.** The backend has no authentication BY
   DESIGN — so it must never be exposed to the internet. Remote access =
   Tailscale. Never add port-forwarding, tunnels, or public hosting.
4. **Never condescending output.** She is an adult with full comprehension.
   The persona layer (backend/app/profile.py) biases register only — no
   dialect costume, no childish phrasing. When tuning, realistic > flavorful.
5. **No time pressure in the UI.** Nothing auto-dismisses, nothing times out
   on her. Errors are calm and tell her what to do next.
6. **Models are config, not code.** Model names live in .env /
   environment (VLLM_MODEL etc.). Swapping models must never require code
   changes; if it does, that's a bug to fix at the config layer.

## On the Spark: your mission

1. Read `spark/README.md`; run setup.sh → build whisper image → compose up.
2. `spark/smoke_test.sh` must pass fully before the tablet points here.
3. Then tune quality against REAL output (this is the important part):
   - Tap words in the web client (http://localhost:8080). Judge sentences
     as *her* candidate utterances: short, first-person, varied
     practical/emotional, speakable aloud.
   - The product's voice lives in `backend/app/llm.py` (BASE_SYSTEM_PROMPT,
     temperature, max_tokens) and `backend/app/profile.py` (era/region
     register). Tune there; keep changes byte-stable per invariant 2.
   - Latency budget: tap → sentences ≲ 2s warm. If slower, check prefix
     cache hits in vLLM logs before touching anything else.
4. Set her real profile (PUT /profile or web Settings): name, birth year,
   region. Verify the register shifts subtly, not into caricature.

## Development facts

- Tests: `cd backend && python -m pytest` (28); `cd mobile && flutter test`
  (30) + `flutter analyze --fatal-infos`. CI runs both + builds the APK
  artifact + iOS simulator compile. Keep all of it green.
- vLLM flags that must NOT be used on GB10: `--enable-chunked-prefill`
  (9x throughput regression), `--kv-cache-dtype fp8` (repetition loops).
- The mobile app's backend address is set in its Settings sheet; give the
  Spark a static IP / DHCP reservation.
- Bookmarks are user-curated only — the AI never auto-saves anything.

## Not yet built (spec features, in rough priority order)

- "My Sentences" screen (all bookmarks grouped by word/category)
- Caregiver word-grid editor (add words to empty slots only; positions of
  existing words are immutable once set)
- Usage-weighted generation (usage_log exists; feed top phrases back in
  without breaking prompt byte-stability — e.g. recompute at profile-update
  granularity, never per-request)
- Phase 2, gated on explicit family authorization: idiolect mining from her
  email, run locally, producing a short style summary (Profile.idiolect_notes
  already flows into the prompt).
