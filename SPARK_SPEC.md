# gb10-02 — Spark spec sheet & connection info

The DGX Spark–class box serving the aphasia-talk stack. Bring-up history
and machine gotchas: [BRINGUP_LOG.md](BRINGUP_LOG.md).

## Hardware / OS

| | |
|---|---|
| Hostname | `gb10-02` |
| Machine | MSI MS-C931 (GB10 Grace Blackwell, DGX Spark class) |
| CPU / RAM | 20-core arm64, **119 GB unified memory** (CPU+GPU pool) |
| GPU | NVIDIA GB10, SM 12.1, driver 580.126.09, CUDA 13.0 |
| Disk | 3.7 TB NVMe (~2.8 TB free) |
| OS | Ubuntu 24.04.4 LTS, kernel 6.17.0-1008-nvidia |

## LAN

| | |
|---|---|
| Interface | `enP7s7` |
| IPv4 | **10.9.8.152/21** (DHCP — ⚠ reservation still needed on the router) |
| MAC (for the reservation) | `fc:9d:05:13:72:54` |
| Gateway | 10.9.8.1 |
| SSH | `ssh ctrlh@10.9.8.152` (port 22, active) |

## Connection points

| Service | URL | Who uses it |
|---|---|---|
| Web client + backend API | `http://10.9.8.152:8080/` | Tablet app ("Speech computer address" in Settings), browser testing |
| vLLM (OpenAI-compatible) | `http://10.9.8.152:8000/v1` | Backend only — do not point clients here |
| whisper.cpp server | `http://10.9.8.152:8001` | Backend only |

**The tablet needs exactly one setting**: `http://10.9.8.152:8080` in the
app's Settings sheet. LLM and speech-to-text are proxied by the backend.

## Security posture

- **No authentication anywhere, by design → LAN only.** Never
  port-forward, tunnel, or host these ports publicly.
- Remote access, when wanted: install Tailscale on the Spark + tablet and
  use the tailnet IP in the app. (Not installed yet.)

## Serving stack (docker compose, repo at /home/ctrlh/aphasia-talk)

| Piece | Value |
|---|---|
| LLM | `nvidia/Qwen3.6-35B-A3B-NVFP4` (vision-capable MoE, 3B active) at `/home/ctrlh/models/Qwen3.6-35B-A3B-NVFP4` |
| vLLM image | `ghcr.io/aeon-7/aeon-vllm-ultimate@sha256:6a79853264…` (vLLM 0.23.0 source-built for GB10 NVFP4; digest-pinned in `.env`) |
| STT | whisper.cpp large-v3-turbo, image `whisper-cpp-server:sm121` (built on-box) |
| TTS | on-device (tablet system voices) — nothing on this box |
| Restart policy | `unless-stopped` on everything — survives reboots/power cuts |
| Boot time | vLLM ~3-5 min after restart (CUDA-graph cache in `./data/vllm-cache`), ~10-12 min if that cache is ever wiped |
| Warm latency | tap → sentences ~1.7-2.1 s |

## Care & feeding

```bash
cd /home/ctrlh/aphasia-talk
docker compose ps                    # state
docker compose logs vllm --tail 50   # LLM logs
./spark/smoke_test.sh                # full end-to-end check (must pass)
docker compose up -d                 # (re)start everything
```

- Machine quirks (no passwordless sudo, unregistered nvidia docker
  runtime → runc/CDI override, dead upstream `cu130-nightly` tag): see
  BRINGUP_LOG.md before changing the runtime setup.
- A pre-existing vLLM container `qwen36` (unrelated 27B model) is stopped;
  `docker start qwen36` restores it, but it cannot run at the same time as
  this stack (port 8000 + memory).
