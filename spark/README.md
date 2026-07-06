# DGX Spark Bring-Up

Turns the Spark from "test backend" into the real backend on your LAN.
Everything here is designed to be run **on the Spark itself** — ideally in a
Claude Code session on the box, so problems get fixed on the spot.

## Prerequisites

- Ubuntu + NVIDIA driver 580.x + CUDA 13 (per SPEC.md)
- Docker with the NVIDIA container runtime (`nvidia-ctk runtime configure`)
- ~60 GB free disk for models
- This repo cloned on the Spark

Running Claude Code on the Spark? The repo-root `CLAUDE.md` is the agent
briefing — it loads automatically and contains the mission, the invariants,
and where the product's voice lives.

## Bring-up order

```bash
# 0. Configuration (models are config, not code)
cp .env.example .env    # repo root; edit if using a different model

cd spark

# 1. Download models (~37 GB total; resumable if interrupted)
./setup.sh

# 2. Build the whisper.cpp server image (one-time, ~10 min)
docker build -t whisper-cpp-server:sm121 ./whisper

# 2b. Build the voice-cloning TTS image (one-time; powers the tablet's
#     "Her voice" option — the stack runs fine without it, speech falls
#     back to the tablet's built-in voice)
docker build -t aphasia-tts:qwen3 ./tts

# 3. Start the stack (from the repo root)
cd .. && docker compose up -d

# 4. Wait for vLLM to load the model (first start takes minutes), then verify
./spark/smoke_test.sh
```

`smoke_test.sh` exercises every endpoint against the real models and prints
latency numbers. Do not point the tablet at the Spark until it passes.

## Known gotchas (from SPEC.md — do not "fix" these)

- **DO NOT** add `--enable-chunked-prefill` to vLLM — 9x throughput
  regression on this hardware.
- **DO NOT** set `--kv-cache-dtype fp8` — output repetition loops on GB10.
- Keep the system prompt byte-stable (it is composed once per profile
  change); prefix caching is what makes taps feel instant.

## Verifying quality, not just liveness

After the smoke test passes, do a manual pass with the web client
(`http://<spark-ip>:8080/`):

1. Tap 10-15 words across categories. Sentences should be first-person,
   short, varied (practical + emotional), never condescending.
2. Set the real profile in Settings (name, birth year, region) and re-tap —
   the voice should shift subtly, not turn into a costume.
3. Photograph a few household objects — identification should be right and
   the sentences usable.
4. Time it: tap → first sentences visible should feel ~1-2s. If it's slower,
   check `docker logs aphasia-vllm` for prefix-cache hits.

Tune `backend/app/llm.py` (SYSTEM prompt, temperature, max_tokens) against
what you see — that file is the product's voice.

## Appliance hardening

The compose file sets `restart: unless-stopped` on everything, so the stack
survives reboots and crashes — this must behave like an appliance, not a dev
server. After a power cut, the Spark should come back speaking on its own.

## Remote access (later)

Do NOT port-forward or expose the backend publicly — it has no auth by
design. For away-from-home use, install Tailscale on the Spark and the
tablet, then use the Spark's tailnet IP as the backend address in the app.

## LAN address

Give the Spark a static IP (DHCP reservation on your router). The tablet's
backend address should never change — a communication aid that needs
reconfiguring is broken from its user's perspective.
