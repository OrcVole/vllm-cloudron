# ADR 0001: CPU-only inference

Status: accepted, 2026-07-30.

## Context

vLLM's native and fastest mode is GPU (CUDA) inference, and upstream ships CUDA images and
wheels as the default. Two independent facts rule that out here:

1. **The platform cannot pass a GPU into an app container.** As of 2026-07-30 the Cloudron
   manifest offers no GPU or device passthrough; the only hardware capability is `vaapi`
   (video transcode via `/dev/dri`). The official Ollama package is CPU-only for the same
   reason. The roadmap position, checked on 2026-07-30: no committed GPU item exists. The
   staff-authored "What's coming in Cloudron 10" thread (April to July 2026) contains no
   GPU, NVIDIA, CDI or device-passthrough entry; the strongest staff statement remains
   November 2025 ("second step is to enable GPU/VAAPI support in docker; this requires
   some complex automation"), with no follow-up since. The most recent movement is a
   community analysis (July 2026) noting that Docker now ships Container Device Interface
   support natively (Docker 25+, default-on in 28.x, and Cloudron 9 runs Docker 28.1.1),
   so the historical "patched Docker" objection no longer applies; that proposal is
   unanswered by staff. So even a GPU-equipped host could not offer the device to this
   app through supported platform means today, but the technical gap has narrowed to a
   platform decision rather than an ecosystem blocker.
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
