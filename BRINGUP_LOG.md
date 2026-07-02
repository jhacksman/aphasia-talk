# Bring-up log — gb10-02 (started 2026-07-02)

Resumable log of the Spark bring-up. If a session dies, read this top to
bottom and continue at the first unchecked step. Keep it updated as you go.

## Machine survey (done 2026-07-02)

- **Host**: gb10-02 — MSI MS-C931 (DGX Spark clone, GB10), arm64, 20 cores,
  119 GB unified memory, 3.7 TB NVMe (2.8 TB free). Ubuntu 24.04.4,
  kernel 6.17.0-1008-nvidia, driver 580.126.09, CUDA 13.0.
- **LAN IP**: 10.9.8.152/21 on enP7s7 (dynamic DHCP — needs a reservation
  before the tablet points here; see spark/README.md "LAN address").
- **Docker**: 29.1.3, compose v5.0.1. nvidia-container-toolkit installed but
  the `nvidia` runtime is NOT registered in /etc/docker/daemon.json (no
  daemon.json exists). The compose file uses `runtime: nvidia`, so this must
  be configured (step 2 below).
- **Node**: 22.23.1 via nvm (installed this session; system node 18 still at
  /usr/local — nvm shadows it in login shells).
- **Python**: 3.12.3 system.

## Pre-existing tenant: `qwen36` container

- vLLM serving `sakamakismile/Qwen3.6-27B-NVFP4` on **port 8000**, ~94 GB
  GPU mem, `restart: unless-stopped`, started via `--gpus all` on runc.
- Last real request: **2026-04-24** (from 10.9.10.214) — idle 2+ months.
- **Conflicts with the stack** (port 8000 + memory), and it runs with the
  flags forbidden on GB10 (`--enable-chunked-prefill`, `--kv-cache-dtype
  fp8`), so it cannot serve as the app's LLM.
- Action: `docker stop qwen36` (container kept, not removed).
  **To restore it later: `docker start qwen36`.**
- Other pre-existing junk: `~/models/Qwen3.5-122B-A10B-heretic-nvfp4` (67 GB,
  unrelated), 116 GB in ~/.cache/huggingface. Left untouched; disk is ample.

## Bring-up steps

- [x] 0. Clone repo → /home/ctrlh/aphasia-talk (branch
       devin/1781755123-project-spec, the origin default)
- [x] 1. `.env` from .env.example with `MODELS_DIR=/home/ctrlh/models`
       (example's /home/user/models doesn't exist here). Model:
       Qwen/Qwen3.6-35B-A3B-FP8 (default, ~35 GB).
- [x] 2. qwen36 stopped. nvidia runtime NOT registered (needs sudo password
       we don't have); instead `docker-compose.override.yml` forces
       `runtime: runc` — GPU access via CDI/--gpus verified working
       (`docker run --rm --gpus all nvidia/cuda:13.0.0-base-ubuntu24.04
       nvidia-smi -L` → GB10). If sudo becomes available, registering the
       runtime properly + deleting the override is the cleaner appliance fix.
- [~] 3. Model download RUNNING in background:
       `MODELS_DIR=/home/ctrlh/models LLM_REPO=nvidia/Qwen3.6-35B-A3B-NVFP4
       spark/setup.sh`. hf CLI installed via
       `pip3 install --user --break-system-packages 'huggingface_hub[cli]'`
       (~/.local/bin, not on default PATH). Non-fatal permission warnings:
       ~/.cache/huggingface/{hub,xet} are root-owned from old container
       runs; downloads go to /home/ctrlh/models regardless. If a resume is
       needed, re-run the same command — it's resumable.

       **Model switched FP8 → NVFP4 (2026-07-02, per Jack).** Research:
       Qwen3.6-35B-A3B is a vision-language MoE (3B active) — covers
       /generate AND /vision. Chose nvidia/Qwen3.6-35B-A3B-NVFP4 (official
       ModelOpt quant, Apache-2.0, ~20 GB vs 35 GB FP8, near-lossless
       benchmarks: MMLU-Pro 85.0 vs 85.6 BF16, MMMU-Pro 74.5 vs 74.1).
       GB10 has native FP4 tensor cores (NVIDIA claims up to 2.5x
       throughput vs FP8); NVFP4 proven on this exact box+image (qwen36 ran
       a sakamakismile NVFP4 for months). vLLM auto-detects modelopt quant
       (qwen36 needed no --quantization flag). NVIDIA's own DGX Spark flags
       suggest kv-cache fp8 + chunked prefill, but repo SPEC forbids both
       from observed failures on this stack — keeping repo gotchas.
       Partial FP8 download (~1 GB) left at
       /home/ctrlh/models/Qwen3.6-35B-A3B-FP8; delete or resume freely.
       Fallback if NVFP4 vision misbehaves: revert .env to
       Qwen/Qwen3.6-35B-A3B-FP8 and resume that download.
- [x] 4. whisper image built: whisper-cpp-server:sm121 (2.56 GB,
       sha 3fd5ff3b95b7, CUDA_ARCH=121, whisper.cpp v1.8.2).
- [~] 5. `docker compose up -d` — three issues found and fixed:
       a) vLLM served by HF repo id would re-download 22 GB (vLLM's
          --download-dir uses hub cache layout, ignores setup.sh's plain
          dir) → .env now sets VLLM_MODEL=/models/Qwen3.6-35B-A3B-NVFP4
          (the in-container mount path).
       b) Current cu130-nightly image entrypoint is already
          ["vllm","serve"]; base compose command doubled it → override
          file now carries the command without the prefix.
       c) whisper-server crash-looped: runtime image missing libgomp1 →
          fixed spark/whisper/Dockerfile (REPO FIX, worth upstreaming),
          rebuilt. Whisper now loads the model fine.
       d) vLLM engine crashes loading the NVFP4 checkpoint — KeyError
          'layers.0.mlp.experts.w2_input_scale'. Re-pulled cu130-nightly:
          the Hub tag itself is stale (last pushed ~2026-04-22, v0.19.2rc1)
          and has the SAME bug. The upstream cu130-nightly tag is dead —
          do not chase it again.
       e) SOLUTION: ghcr.io/aeon-7/aeon-vllm-ultimate:latest — vLLM 0.23.0
          source-built for GB10/sm_121a with working NVFP4 kernels (GB10
          lacks the e2m1 PTX instruction; this image carries the software
          conversion + marlin MoE backend). The NVIDIA-forum benchmark ran
          nvidia/Qwen3.6-35B-A3B-NVFP4 on exactly this image; vision fixed
          as of the 2026-06-18 build. Its entrypoint is /bin/bash →
          override sets entrypoint ["vllm","serve"]. Added
          ./data/vllm-cache volume (persists CUDA graphs; first boot
          ~10-12 min, later boots ~3-5 min). .env: VLLM_IMAGE now the AEON
          image. TODO after it works: pin by digest (community image;
          appliance shouldn't float on :latest).
          Optional later: DFlash speculative decoding (needs a drafter
          model; big decode speedup per AEON docs — evaluate after smoke
          test).
       NOTE: this vLLM version enables chunked prefill BY DEFAULT (v1
       engine). The repo's "--enable-chunked-prefill forbidden" gotcha may
       be stale for current vLLM; watch smoke-test latency before fighting
       it.
- [x] 6. Smoke test: ALL PASSED (2026-07-02 ~13:20 UTC). Warm /generate
       1.68-1.73 s (target ≤2.5 s). Three fixes were needed first:
       a) backend/app/llm.py: Qwen3.6 ignores the legacy "/no_think" soft
          switch → added chat_template_kwargs {"enable_thinking": false}
          to both /generate and /vision request bodies; also guard
          content=None (was an uncaught AttributeError → 500).
       b) backend/app/config.py: request_timeout 30→120 s (first inference
          after cold boot autotunes kernels ~60 s; UI shows no timer).
       c) spark/smoke_test.sh: f-string \" escapes are a SyntaxError on
          Python 3.12 — the assertions had never actually run. Rewrote
          three snippets without escapes.
       Backend pytest suite: 22 passed (run in container).
- [x] 7. Quality pass over 6 words across categories (family, tired,
       outside, music, morning, sorry): first-person, short, practical +
       emotional mix, dignified ("My mind is not working well today",
       "It is hard to find the right words"). Fixed duplicate
       related_words with a case-insensitive dedupe in _coerce_payload.
       NOT DONE: her real profile (name, birth year, region) — needs Jack
       (PUT /profile or web Settings), then re-judge register per
       CLAUDE.md.
- [x] 7b. Pinned VLLM_IMAGE to the digest
       (ghcr.io/aeon-7/aeon-vllm-ultimate@sha256:6a79853264...) so the
       appliance never floats on :latest. vLLM restarts boot in ~3-5 min
       thanks to the ./data/vllm-cache volume.
- [ ] 8. Ops, still open:
       - DHCP reservation for 10.9.8.152 (router — needs the human).
       - Tablet: set backend address http://10.9.8.152:8080 in Settings.
       - Tailscale for remote use (later). Never expose publicly.
       - Repo fixes worth committing/upstreaming: llm.py thinking+None
         guards, config timeout, smoke_test.sh f-strings, whisper
         Dockerfile libgomp1. Local-only files: .env,
         docker-compose.override.yml, BRINGUP_LOG.md.
       - Optional perf: DFlash speculative decoding (AEON drafter) if
         faster decode ever matters; current latency already in budget.

## Session notes

- 2026-07-02: Survey done. Log created. Proceeding with steps 1-2.
- 2026-07-02 (later): BRING-UP COMPLETE. Final smoke test fully green on
  the digest-pinned stack (warm /generate 1.7-2.1 s). Stack: AEON vLLM
  (0.23.0, GB10 NVFP4 kernels) + nvidia/Qwen3.6-35B-A3B-NVFP4 (vision
  capable) + whisper-cpp-server:sm121 + backend. All restart:
  unless-stopped. Remaining for the human: DHCP reservation, tablet
  backend address, her real profile, then re-judge register. Uncommitted
  repo changes listed in step 8 — commit when Jack says so.
