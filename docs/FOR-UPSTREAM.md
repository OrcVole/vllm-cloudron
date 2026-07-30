# Notes for the vLLM developers

Observations from packaging vLLM 0.26.0 (CPU backend) for a self-hosting platform,
offered gratefully; each cost this packager an afternoon and could cost the next one
nothing. Everything was verified against v0.26.0 on real hosts. The same points appear
in the upstream show-and-tell post.

## 1. A liveness endpoint that answers before model load

`/health` answers only after model load and engine initialisation complete. On any
platform that health-checks during startup (Cloudron, Kubernetes, most orchestrators),
a first boot that downloads a model is killed mid-download unless the packager fronts
the server with a proxy that answers liveness immediately. A native early-binding
liveness endpoint, with readiness split out (the discussion in issue #6073 pointed this
direction), would remove that shim for every orchestrated deployment.

## 2. Document that `--max-model-len` is effectively mandatory on small-memory hosts

A model's declared context can exceed the CPU backend's KV cache budget on its own:
the 0.6B default model declares a 40960-token context, which needs 4.4 GiB of KV
against the backend's 4 GiB default, and the engine exits. The error message itself is
excellent. One sentence in the CPU installation docs saying "cap `--max-model-len` or
raise `VLLM_CPU_KVCACHE_SPACE`; defaults will not fit small hosts" would turn a
failed first boot into a config choice.

## 3. State that `VLLM_*` is a reserved environment namespace

The boot-time warning for unknown `VLLM_`-prefixed variables is a good warning, but
anyone wrapping the server naturally reaches for that prefix for their own settings and
then ships permanent boot noise. A documented statement that the namespace belongs to
vLLM would push wrappers to their own prefix from day one (this package uses `LLM_`).

## 4. A resolver note for uv users installing release wheels

The release wheel's exact `setuptools` pin is unsatisfiable for uv's default
first-index strategy when the PyTorch CPU index is supplied as an extra index; plain
pip resolves it. A line in the CPU install docs would save uv users the confusion,
since uv is otherwise the documented recommendation.

## 5. Official CPU sizing guidance

Self-hosters currently size by trial. Two numbers from this packaging, for whatever
use they are: a 0.6B model at BF16 with the default 4 GiB KV cache idles at roughly
7.4 GiB total (the cache is preallocated, so idle and loaded are nearly identical),
and older AVX2-only hardware streams under one token per second on that model while
AVX-512 hardware is substantially faster. Rough official expectations per instruction
tier, plus a memory rule of thumb (weights + KV cache + roughly 2.5 GiB runtime
overhead was our measurement), would let people size before installing.

## Packaging contact

Package source: https://github.com/OrcVole/vllm-cloudron. Issues and corrections are
welcome; the package ships vLLM unmodified and is unaffiliated with the project.
