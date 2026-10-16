[0.4.0]

- Base image cloudron/base 5.1.0 to 6.0.0 (Ubuntu 26.04). Base 6 carries Python 3.14 and no venv,
  so the package now ships its own CPython 3.12.15, installed by uv under /app/code/python. Same
  Python minor as before; no future base bump can move it.
- Update vLLM 0.30.0 to 0.31.0. A minor, not a patch, because upstream lists breaking changes:
  - Per-request `mm_processor_kwargs` and `media_io_kwargs` are now refused unless the server is
    started with `--trust-request-mm-kwargs` (add it to `LLM_EXTRA_ARGS` only if you trust every
    caller).
  - `tokenizer_mode="slow"` is removed.
  - `--enable-mamba-fine-grained-prefix-cache` is renamed `--enable-mamba-shared-prefix-checkpoint`.
- Security (upstream's own Security section): per-request multimodal kwargs gated (#58830); prefix
  cache keys tagged by source and LoRA paths hashed, so one tenant cannot collide another's cached
  blocks (#51899, #59335); a stale receiver cache no longer overrides fresh multimodal input (#57833);
  upper-case memory addresses filtered from messages (#58832); LoRA adapters named after a served
  model refused (#59286).
- Fix: vLLM 0.31 writes compiled Triton kernels to the home directory, which is read-only on Cloudron,
  so the engine crash-looped on first boot while the dashboard still showed the app as running. The
  kernel cache now lives beside the model cache in /var/lib/vllm (kept across restarts, not backed up).

[0.3.1]

- Update vLLM 0.29.0 to 0.30.0
- New models: DeepSeek-V4.1-Flash, GLM-5.3-Flash, K2-Horizon; Fast Start weight-cache daemon
- Watermarking support and HiSparse tiering improvements
- Scale-out endpoints now opt-in via `--enable-scale-out` flag (env var removed upstream)
- Packaging: no changes required for this Cloudron package
- Base image cloudron/base 5.0.0 to 5.1.0: the Ubuntu 24.04.4 point release, with its OS security
  updates. Same Ubuntu 24.04 release and glibc 2.39.

[0.3.0]

- Update vLLM 0.28.0 to 0.29.0
- Model Runner V2 is now the default engine; new model support includes Hy4-preview, Qwen3.8-Flash-Next, GraniteSWA/MoE and Kimi K3 NVFP4
- Performance improvements across CUDA ROCm and CPU backends
- New opt-in ASGI authentication middleware (available via `--api-key`)
- Ten deprecated model architectures removed: Arctic, Chameleon, Cheers, Fairseq2Llama, FireRedLID, GritLM, HCXVision, MPT, RWForCausalLM/StableLMEpochForCausalLM aliases and PrithviGeoSpatialMAE
- PyAV video decoder backend removed; use OpenCV or Torchcodec instead
- Environment variables `VLLM_TEST_FORCE_FP8_MARLIN` and `VLLM_ROCM_USE_AITER_FP4_ASM_GEMM` removed
- FlashInfer all-reduce now enabled by default for TP CUDA groups (opt out with `VLLM_ALLREDUCE_USE_FLASHINFER=0`)
- Check before updating: vLLM 0.29 removes the ten model architectures listed above and makes Model Runner V2 the
  default engine. If your install serves one of those models, or passes a removed option or environment variable
  through `LLM_EXTRA_ARGS`, it will fail to start on this version; change the model or options first.

[0.2.1]

- Update vLLM 0.27.1 -> 0.28.0
- Security: fixes prevent denial of service via forged audio sample rates and oversized image inputs, unauthenticated access to API endpoints, arbitrary code execution from untrusted model repositories, and resource exhaustion from unbounded generation requests
- Breaking: bitsandbytes quantization moved to an out-of-tree plugin; Transformers dependency bumped to 5.15.0; removed flags `calculate_kv_scales` and `override_attention_dtype`; `reasoning_content` no longer included in output; MoE legacy code paths removed; `cache_salt` now required to be non-empty
- Behaviour changes: `max_num_batched_tokens` default raised to 16384; prefix caching now enabled by default for Mamba models; Blackwell CUDA graph capture default raised to 1024; KV offload tiering metrics renamed from block to chunk
- Packaging: pin moved; /dev/shm detection in start.sh unchanged and still required

[0.2.0]

- vLLM 0.27.1 (from 0.26.0), which upstream calls a breaking environment change: PyTorch moves to 2.13.0 with torchvision 0.28.0 and Triton 3.7.1
- Upstream removed the `max_num_partial_prefills` and `max_long_partial_prefills` arguments and dropped the Plamo2 and Ouro models; this package used none of them, so no packaging change was needed
- New models available upstream include Qwen3.5 dense and MoE, K-EXAONE-2.0, VaultGemma and jina-embeddings-v5-text-nano
- Packaging fix required by 0.27.x: its engine now runs in a separate process and brokers work over a shared-memory ring buffer needing 160 MiB of /dev/shm, while a Cloudron app container has a fixed 64 MiB. The app would not have started at all. start.sh now measures /dev/shm at boot and runs the engine in-process when it is under 200 MiB, which costs nothing on a single-model CPU server, and logs which mode it chose. Written as a measurement rather than a constant, so the package returns to upstream's default automatically if the platform limit ever rises

[0.1.0]

- Initial release: vLLM 0.26.0 OpenAI-compatible inference server, CPU backend (amd64, AVX2 minimum)
- One model per install, default Qwen/Qwen3-0.6B, configurable via LLM_MODEL
- Generated API key protects /v1; health, readiness and landing page open
- Model cache on a persistent path outside backups; restores stay small and fast
- Full gate ladder passed: install, auth, streamed flows through the platform proxy, backup/restore, memory sizing (10 GiB limit from measured 7.4 GiB steady footprint)
