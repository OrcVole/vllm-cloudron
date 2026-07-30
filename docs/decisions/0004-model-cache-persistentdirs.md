# ADR 0004: model cache on persistentDirs, key and config in /app/data

Status: implemented 2026-07-30, acceptance pending Gate 3 restore evidence.

Implementation notes (from a sibling package's hard-won precedent): the persistentDirs
path lives OUTSIDE /app/data (`/var/lib/vllm`), matching the proven pattern; the mount
arrives root-owned so start.sh chowns it every boot; no `backupCommand`/`restoreCommand`
are declared because the cache is fully reproducible and the correct restore behaviour is
a re-download, not a dump (the manifest reference suggests pairing with backupCommand;
deliberately not done here, verified in Gate 3). Introduced before first publish because
adding a persistentDir to an already-published package orphans existing users' data
without a one-time in-place migration.

## Context

Model weights are multi-gigabyte and fully reproducible from the network; the API key and
operator configuration are tiny and irreplaceable. A naive layout puts the Hugging Face cache
in plain `/app/data`, where the platform's live backup walks and stores it on every run: dead
weight in every backup, and multi-GB churn risk for the whole server's backup window.

`persistentDirs` excludes a path from the filesystem backup while letting it survive restarts
and updates; the cost is that a restore or clone starts the path empty.

## Decision

- `/var/lib/vllm` declared under `persistentDirs`: holds `HF_HOME` (weights and hub state)
  and `VLLM_CACHE_ROOT` (vLLM's compiled-artifact cache).
- The key (`/app/data/.secrets/keys.env`) and configuration stay on the normal backed-up path.
- First boot, and first boot after a restore or clone, downloads the model; the health
  arrangement (ADR 0003) makes that survivable and visible.

## Consequences

- Backups stay small and fast regardless of model size.
- Verified in Gate 3: an in-place restore keeps the persistentDir intact, so ordinary
  restores do not pay a re-download; a fresh install (and, per platform semantics, a clone
  to a new location) starts empty and re-downloads unattended. The README says so.
- Gate 3 must prove: key sha256 identical across update and restore; model cache absent after
  restore; app reaches ready state again unattended.
- `minBoxVersion` 9.1.0 (the floor for `persistentDirs`, and for the community versions
  channel anyway).
