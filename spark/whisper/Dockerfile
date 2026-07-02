# whisper.cpp HTTP server with CUDA for the DGX Spark (arm64 + SM121).
#
# Built on the Spark itself: docker build -t whisper-cpp-server:sm121 .
# NOT built in CI (needs an arm64 CUDA toolchain); the smoke test validates it.
#
# WHISPER_CPP_REF pins the source; bump it deliberately, models change weekly
# but the runtime shouldn't churn underneath the family.
ARG CUDA_IMAGE=nvcr.io/nvidia/cuda:13.0.0-devel-ubuntu24.04
ARG CUDA_RUNTIME_IMAGE=nvcr.io/nvidia/cuda:13.0.0-runtime-ubuntu24.04
FROM ${CUDA_IMAGE} AS build

ARG WHISPER_CPP_REF=v1.8.2
# SM121 (GB10). Override if nvcc complains: --build-arg CUDA_ARCH=121
ARG CUDA_ARCH=121

RUN apt-get update && apt-get install -y --no-install-recommends \
        git cmake build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${WHISPER_CPP_REF} \
        https://github.com/ggml-org/whisper.cpp /src
WORKDIR /src

RUN cmake -B build \
        -DGGML_CUDA=1 \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
        -DBUILD_SHARED_LIBS=OFF \
    && cmake --build build -j"$(nproc)" --target whisper-server

FROM ${CUDA_RUNTIME_IMAGE} AS runtime
# ggml links OpenMP dynamically even with BUILD_SHARED_LIBS=OFF; the CUDA
# runtime image doesn't ship libgomp.
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/bin/whisper-server /usr/local/bin/whisper-server

EXPOSE 8001
ENTRYPOINT ["whisper-server", "--host", "0.0.0.0", "--port", "8001"]
# Model is mounted at runtime: --model /models/ggml-large-v3-turbo.bin
