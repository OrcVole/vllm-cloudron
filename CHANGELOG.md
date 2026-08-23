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
