# vLLM packaged for Cloudron, CPU backend.
#
# Two-stage build (ADR 0002): the builder creates a self-contained venv on the same base the
# runtime uses, so the runtime stage ships only the installed tree and no wheel-cache cruft.
# The upstream version is pinned by VLLM_VERSION and installed from the exact GitHub release
# wheel (vllm-<ver>+cpu), with torch resolved from the PyTorch CPU index so nothing ever pulls
# the multi-gigabyte CUDA torch (field guide gotcha #2). A future GPU variant swaps the +cpu
# wheel for the +cu129 wheel published in the same upstream release (ADR 0001).

ARG VLLM_VERSION=0.30.0

# --- Stage 1: builder ----------------------------------------------------------------------
FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c AS builder
ARG VLLM_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends python3.12-venv \
    && rm -rf /var/lib/apt/lists/*

ENV VENV=/app/code/venv
RUN python3.12 -m venv ${VENV} && ${VENV}/bin/pip install --no-cache-dir --upgrade pip uv

# CPU torch first, so the vLLM install finds torch already satisfied from the CPU index.
RUN ${VENV}/bin/uv pip install --python ${VENV}/bin/python \
      --index-url https://download.pytorch.org/whl/cpu torch

# The pinned upstream CPU wheel, with pip exactly as the upstream CPU install docs specify.
# pip, not uv, for this step: uv's first-index strategy cannot satisfy the wheel's exact
# setuptools pin against the PyTorch CPU extra index (observed 2026-07-30, v0.26.0).
RUN ${VENV}/bin/pip install --no-cache-dir \
      "https://github.com/vllm-project/vllm/releases/download/v${VLLM_VERSION}/vllm-${VLLM_VERSION}+cpu-cp38-abi3-manylinux_2_39_x86_64.whl" \
      --extra-index-url https://download.pytorch.org/whl/cpu

# Intel OpenMP: the upstream CPU docs recommend LD_PRELOADing libiomp5.so with the prebuilt
# wheels. Installed here so start.sh can preload it if present; harmless if unused.
RUN ${VENV}/bin/uv pip install --python ${VENV}/bin/python intel-openmp || \
    echo "intel-openmp not installed; start.sh will fall back to default OpenMP"

# Build gate (linkage only; the real gate is the runtime smoke test): imports resolve on this
# base, torch is the CPU build, and CUDA is genuinely absent.
RUN ${VENV}/bin/python - <<'PY'
import torch, vllm
assert torch.__version__.endswith("+cpu"), torch.__version__
assert not torch.cuda.is_available()
print("build gate ok:", vllm.__version__, torch.__version__)
PY

# --- Stage 2: runtime ----------------------------------------------------------------------
FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c
ARG VLLM_VERSION
# Not named VLLM_VERSION at runtime: vLLM treats VLLM_* as its own env namespace and warns
# about unknown members on every boot.
ENV UPSTREAM_VERSION=${VLLM_VERSION}

RUN mkdir -p /app/code
WORKDIR /app/code

COPY --from=builder /app/code/venv /app/code/venv
COPY nginx.conf /app/code/nginx.conf
COPY www/ /app/code/www/
COPY start.sh /app/code/start.sh
RUN chmod 0755 /app/code/start.sh

LABEL org.opencontainers.image.title="vllm-cloudron" \
      org.opencontainers.image.description="vLLM OpenAI-compatible inference server (CPU) packaged for Cloudron" \
      org.opencontainers.image.licenses="Apache-2.0"

# CMD, never ENTRYPOINT (ENTRYPOINT breaks Cloudron debug mode).
CMD [ "/app/code/start.sh" ]
