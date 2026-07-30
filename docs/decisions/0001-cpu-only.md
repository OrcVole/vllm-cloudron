# ADR 0001: CPU-only inference

Status: accepted, 2026-07-30.

## Context

vLLM's native and fastest mode is GPU (CUDA) inference, and upstream ships CUDA images and
wheels as the default. Two independent facts rule that out here:

1. **The platform cannot pass a GPU into an app container.** As of 2026-07-30 the Cloudron
   manifest offers no GPU or device passthrough; the only hardware capability is `vaapi`
   (video transcode via `/dev/dri`). The official Ollama package is CPU-only for the same
   reason, and staff describe GPU support as possible future work with no committed plan.
   A community proposal to adopt Docker's native Container Device Interface exists on the
   forum but is unanswered. So even a GPU-equipped host could not offer the device to this
   app through supported platform means.
2. Typical Cloudron hosts, including the reference deployment, have no GPU.

vLLM's CPU backend is officially supported on amd64 (AVX512 fast path, AVX2 reduced) with
prebuilt wheels and an official CPU image, so a CPU package is buildable and honest.

## Decision

Package vLLM's CPU backend only. State the performance reality plainly in every user-facing
text. Do not carry dormant CUDA weight in the image.

## Consequences

- The image stays small (the CPU dependency tree is roughly a fifth of the CUDA one).
- Throughput claims must be modest and measured, not copied from upstream GPU benchmarks.
- **If Cloudron ships GPU passthrough, this decision is revisited**: the intended path is a
  parallel CUDA image variant (same manifest, larger image, `--gpus`-equivalent capability),
  not a rebuild of this package's architecture. The env-driven configuration and the
  nginx/health arrangement carry over unchanged.
- Users who need GPU speed today can run an OpenAI-compatible server on GPU hardware outside
  the platform and route to it with an AI gateway; that pattern is documented generically in
  the README of the gateway-style packages, not here.
