# ADR 0004: model cache on persistentDirs, key and config in /app/data

Status: proposed, 2026-07-30. To be proven in Gate 3 before it becomes accepted.

## Context

Model weights are multi-gigabyte and fully reproducible from the network; the API key and
operator configuration are tiny and irreplaceable. A naive layout puts the Hugging Face cache
in plain `/app/data`, where the platform's live backup walks and stores it on every run: dead
weight in every backup, and multi-GB churn risk for the whole server's backup window.

`persistentDirs` excludes a path from the filesystem backup while letting it survive restarts
and updates; the cost is that a restore or clone starts the path empty.

## Decision

- `/app/data/models` (exact path settled in Phase 3) declared under `persistentDirs`: holds
  `HF_HOME`, the weight cache, and `VLLM_CACHE_ROOT` (vLLM's compiled-artifact cache).
- The key (`/app/data/.secrets/keys.env`) and configuration stay on the normal backed-up path.
- First boot, and first boot after a restore or clone, downloads the model; the health
  arrangement (ADR 0003) makes that survivable and visible.

## Consequences

- Backups stay small and fast regardless of model size.
- A restored or cloned install needs network access to the model source and a slow first boot.
  The README says so.
- Gate 3 must prove: key sha256 identical across update and restore; model cache absent after
  restore; app reaches ready state again unattended.
- `minBoxVersion` 9.1.0 (the floor for `persistentDirs`, and for the community versions
  channel anyway).
