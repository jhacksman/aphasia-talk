#!/usr/bin/env bash
# Download the models the stack needs. Run on the DGX Spark. Resumable.
set -euo pipefail

# Everything is overridable — model quality moves weekly, so the stack treats
# models as configuration. To try a different LLM:
#   LLM_REPO=SomeOrg/some-model ./setup.sh
# then set the same name in .env (VLLM_MODEL) and `docker compose up -d`.
MODELS_DIR="${MODELS_DIR:-$HOME/models}"
LLM_REPO="${LLM_REPO:-Qwen/Qwen3.6-35B-A3B-FP8}"
WHISPER_URL="${WHISPER_URL:-https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin}"

echo "==> Models directory: $MODELS_DIR"
mkdir -p "$MODELS_DIR/whisper"

# --- Qwen weights (~35 GB) -------------------------------------------------
# vLLM can pull from the Hub itself, but pre-downloading makes startup
# deterministic and survives compose restarts without re-checking the network.
if ! command -v hf >/dev/null 2>&1 && ! command -v huggingface-cli >/dev/null 2>&1; then
    echo "==> Installing huggingface_hub CLI"
    pip install --user -q "huggingface_hub[cli]"
    export PATH="$HOME/.local/bin:$PATH"
fi
HF_CLI=$(command -v hf || command -v huggingface-cli)

echo "==> Downloading $LLM_REPO (~35 GB, resumable)"
"$HF_CLI" download "$LLM_REPO" --local-dir "$MODELS_DIR/$(basename "$LLM_REPO")"

# --- Whisper GGUF (~1.5 GB) ------------------------------------------------
WHISPER_BIN="$MODELS_DIR/whisper/ggml-large-v3-turbo.bin"
if [ -f "$WHISPER_BIN" ]; then
    echo "==> Whisper model already present, skipping"
else
    echo "==> Downloading Whisper large-v3-turbo"
    curl -L --fail --retry 3 -C - -o "$WHISPER_BIN" "$WHISPER_URL"
fi

echo
echo "==> Done. Models in $MODELS_DIR:"
du -sh "$MODELS_DIR"/* 2>/dev/null
echo
echo "Next: docker build -t whisper-cpp-server:sm121 ./whisper"
echo "Then: docker compose up -d   (from the repo root)"
