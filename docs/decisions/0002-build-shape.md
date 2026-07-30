# ADR 0002: build shape, CPU wheels onto cloudron/base

Status: accepted, 2026-07-30. Execution pending (Phase 2).

## Context

The final image stage must be `cloudron/base` (platform tooling depends on its userland).
Three candidate shapes for getting vLLM there:

1. Copy the upstream `vllm/vllm-openai-cpu` image's Python environment across (the pattern a
   sibling package used for a single Rust binary plus its MKL runtime). A full cross-distro
   Python venv copy is brittle: interpreter, native libs and dlopened libs must all line up.
2. Build vLLM from source on the base. Slow, toolchain-heavy, unnecessary now that wheels
   exist.
3. Install the pinned release's prebuilt CPU wheels into a venv on the base itself, CPU torch
   resolved first so nothing pulls the multi-gigabyte CUDA torch. This is the proven pattern
   for Python ML apps in this packaging lineage (a document-parsing package shipped this way),
   and upstream documents the CPU wheel install path.

## Decision

Shape 3: two-stage build, both stages `cloudron/base:5.0.0` pinned by digest. Builder creates
`/app/code/venv` with Python 3.12, installs CPU-only torch from the PyTorch CPU index, then
`vllm==<pinned>` per the upstream CPU install documentation (uv as installer). Runtime stage
copies the venv only. Build gates: `import vllm`; `torch.__version__` ends `+cpu`;
`torch.cuda.is_available()` is False.

## Consequences

- The image ships only the installed tree; builder-layer cruft (wheel caches) never reaches
  the runtime stage.
- The build gate proves linkage only. The shipping gate is a runtime smoke test that completes
  a real chat completion, because torch-family stacks load libraries lazily.
- Fallback if wheel resolution misbehaves on the base: shape 1 (venv copy from the upstream
  Debian-based CPU image, glibc-compatible), accepted as brittle and documented if used.
