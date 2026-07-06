# Qwen3-TTS voice-cloning sidecar for the DGX Spark (arm64 + GB10).
#
# Built on the Spark: docker build -t aphasia-tts:qwen3 spark/tts
# NOT built in CI (arm64 CUDA); spark/smoke_test.sh validates it end to end.
#
# Uses the *Base* variant — the only Qwen3-TTS variant that clones voices
# (CustomVoice does not, despite the name). Model is config: TTS_MODEL env.
ARG CUDA_IMAGE=nvcr.io/nvidia/cuda:13.0.0-runtime-ubuntu24.04
FROM ${CUDA_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv ffmpeg libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# qwen-tts pulls torch; on arm64 this resolves to the aarch64 CUDA wheels.
# If torch/CUDA wheel resolution fails on this box, install torch first from
# the NVIDIA index (see BRINGUP_LOG.md for the pattern used for vLLM).
RUN pip install --no-cache-dir qwen-tts fastapi uvicorn

COPY server.py /srv/server.py

# Weights download on first start into the mounted models volume (HF_HOME).
ENV HF_HOME=/models/hf-cache
ENV TTS_MODEL=Qwen/Qwen3-TTS-12Hz-1.7B-Base

EXPOSE 8002
CMD ["uvicorn", "--app-dir", "/srv", "server:app", "--host", "0.0.0.0", "--port", "8002"]
