# vLLM packaged for Cloudron, CPU backend.
#
# Two-stage build (ADR 0002): the builder creates a self-contained venv on the same base the
# runtime uses, so the runtime stage ships only the installed tree and no wheel-cache cruft.
# The upstream version is pinned by VLLM_VERSION and installed from the exact GitHub release
# wheel (vllm-<ver>+cpu), with torch resolved from the PyTorch CPU index so nothing ever pulls
# the multi-gigabyte CUDA torch (field guide gotcha #2). A future GPU variant swaps the +cpu
# wheel for the +cu129 wheel published in the same upstream release (ADR 0001).

ARG VLLM_VERSION=0.32.0

# --- uv, pinned: it installs the interpreter as well as the packages ------------------------
FROM ghcr.io/astral-sh/uv:0.13.1@sha256:4a1f3666816dafadd20ceb71eac9a7d56d7ef30279f7d64048519ab901ada336 AS uv

# --- Stage 1: builder ----------------------------------------------------------------------
# cloudron/base 6 carries Python 3.14 and no venv or pip. The package pins its own CPython 3.12
# with uv under /app/code/python (base-6-migration.md step 5: preferred for torch and vLLM, whose
# wheels lag new Python releases), so the interpreter travels with the venv and no future base
# bump can move it. The venv's python is a symlink into that tree, so both are copied below.
FROM docker.io/cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee AS builder
ARG VLLM_VERSION
COPY --from=uv /uv /usr/local/bin/uv
ENV VENV=/app/code/venv \
    UV_PYTHON_INSTALL_DIR=/app/code/python \
    UV_PYTHON_PREFERENCE=only-managed
RUN uv python install 3.12.15 \
    && uv venv --python 3.12.15 ${VENV} \
    && uv pip install --python ${VENV}/bin/python pip

# CPU torch first, so the vLLM install finds torch already satisfied from the CPU index.
RUN uv pip install --python ${VENV}/bin/python \
      --index-url https://download.pytorch.org/whl/cpu torch

# The pinned upstream CPU wheel, with pip exactly as the upstream CPU install docs specify.
# pip, not uv, for this step: uv's first-index strategy cannot satisfy the wheel's exact
# setuptools pin against the PyTorch CPU extra index (observed 2026-07-30, v0.26.0).
RUN ${VENV}/bin/pip install --no-cache-dir \
      "https://github.com/vllm-project/vllm/releases/download/v${VLLM_VERSION}/vllm-${VLLM_VERSION}+cpu-cp38-abi3-manylinux_2_39_x86_64.whl" \
      --extra-index-url https://download.pytorch.org/whl/cpu

# Intel OpenMP: the upstream CPU docs recommend LD_PRELOADing libiomp5.so with the prebuilt
# wheels. Installed here so start.sh can preload it if present; harmless if unused.
RUN uv pip install --python ${VENV}/bin/python intel-openmp || \
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
FROM docker.io/cloudron/base:6.0.1@sha256:7b1e729960c3ca312d26e886917ba89483241bba0219ff292858e10d9d5768ee
ARG VLLM_VERSION
# Not named VLLM_VERSION at runtime: vLLM treats VLLM_* as its own env namespace and warns
# about unknown members on every boot.
ENV UPSTREAM_VERSION=${VLLM_VERSION}

# Native libraries base 5 carried incidentally and base 6 does not (measured 2026-10-16 by resolving
# every unresolved soname in the venv against base 5.1.0): libnuma for vLLM's CPU kernels (vllm._C;
# without it the server starts and inference fails), and the FFmpeg runtime libraries torchcodec loads
# for video input (26.04 carries FFmpeg 8, which torchcodec's core8 matches; 24.04 carried 6).
RUN apt-get update \
    && apt-get install -y --no-install-recommends libnuma1 \
       libavcodec62 libavformat62 libavutil60 libswscale9 libswresample6 libavdevice62 libavfilter11 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/code
WORKDIR /app/code

COPY --from=builder /app/code/python /app/code/python
COPY --from=builder /app/code/venv /app/code/venv
COPY nginx.conf /app/code/nginx.conf
COPY www/ /app/code/www/
COPY start.sh /app/code/start.sh
RUN chmod 0755 /app/code/start.sh

# Runtime gate (#291): the exact interpreter and venv start.sh execs resolve on THIS stage, with no
# dependence on the base's own Python.
# Import vllm._C itself: `import vllm` only WARNS when the native kernels fail to load, which is how a
# missing libnuma passed the first base-6 build's gate.
RUN /app/code/venv/bin/python -c 'import sys, torch, vllm, vllm._C; assert sys.version_info[:2] == (3, 12), sys.version; print("runtime gate ok:", sys.version.split()[0], vllm.__version__, torch.__version__)' \
    && /app/code/venv/bin/python -c 'import importlib.util as u; print("torchcodec:", "absent" if u.find_spec("torchcodec") is None else __import__("torchcodec").__version__)' \
    && /app/code/venv/bin/vllm --help >/dev/null

LABEL org.opencontainers.image.title="vllm-cloudron" \
      org.opencontainers.image.description="vLLM OpenAI-compatible inference server (CPU) packaged for Cloudron" \
      org.opencontainers.image.licenses="Apache-2.0"

# CMD, never ENTRYPOINT (ENTRYPOINT breaks Cloudron debug mode).
CMD [ "/app/code/start.sh" ]
