[0.1.0]
* Initial release: vLLM 0.26.0 OpenAI-compatible inference server, CPU backend (amd64, AVX2 minimum)
* One model per install, default Qwen/Qwen3-0.6B, configurable via LLM_MODEL
* Generated API key protects /v1; health, readiness and landing page open
* Model cache on a persistent path outside backups; restores stay small and fast
* Full gate ladder passed: install, auth, streamed flows through the platform proxy, backup/restore, memory sizing (10 GiB limit from measured 7.4 GiB steady footprint)
