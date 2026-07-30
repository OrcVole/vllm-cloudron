# Debugging and gate evidence

Gate ladder evidence tables land here as the gates run: one row per invariant, one column per
condition tested, a proof cell containing the actual evidence (hash prefixes, counts, modes),
and an explicit PASS or FAIL, with enough of the recipe to repeat the gate at the next version
bump.

**Ladder restart, 2026-07-30:** the gates below first passed against digest
`1924e833ef88…`. Implementing ADR 0004 (model cache moved to the `/var/lib/vllm`
persistentDir) changed start.sh and the manifest, so the image was rebuilt and the ladder
restarted at Gate 0 against the new digest, per the ladder rules. The earlier evidence is
kept for the record; the tables are updated per gate as the rerun completes.

Shipping digest: `sha256:254b0295f6c3842d1c6415fe77b26e86578acc7bbd7d82c19cc572b5e8e970d9`.

| Gate | Status | Evidence |
|---|---|---|
| 0 install and first run | PASS 2026-07-30 (digest 254b0295) | tables below; rerun: fresh install ready in ~300 s, key `9c3cc4d7bc4da270` stable across restart, existing-key branch logged, `/var/lib/vllm` mounted by the platform and chowned |
| 1 auth | PASS 2026-07-30 (digest 254b0295) | rerun: `/health` `/ready` `/ping` `/metrics` `/` all 200 r=0; `/v1/models` 401 bare/wrong key, 200 keyed |
| 2 functional flows | PASS 2026-07-30 (digest 254b0295) | streamed 48-token completion 63 s through the proxy (>60 s cut), 50 chunks + `[DONE]`; non-streamed `finish=length`, `completion_tokens=8`; `request_success_total` delta exactly 2 |
| 3 update and restore | PASS 2026-07-30 (restore leg; update leg deferred with reason) | see below |
| 4 memory | PASS 2026-07-30 (digest 254b0295) | see below |

## Gate 4 evidence (2026-07-30)

Restart-route measurement (this host's cgroupfs `memory.peak` refuses reset, as the
platform facts predicted; cgroup path `/sys/fs/cgroup/docker/<id>`). Load recipe: two
sequential 96-token completions, then two concurrent 48-token completions, via localhost,
after warmup on a fresh counter.

| Invariant | Idle | Loaded |
|---|---|---|
| memory current / peak | 7.34 / 7.36 GiB (peak = warmup) | 7.38 / 7.39 GiB |
| oom_kill | 0 | 0 |
| per-process RSS | worker 6.18 GB, api server 1.14 GB, engine core 0.82 GB | worker 6.22 GB, others unchanged |

The footprint is steady-state by construction: the 4 GiB KV cache is preallocated at
engine init, so load moved the total by only ~50 MB. Verdict arithmetic: loaded peak
7.39 GiB is 92% of the original 8 GiB limit (FAIL on the 80% rule) and 74% of 10 GiB;
the worst case (KV cannot grow; API-side concurrency spikes bounded by a few hundred MB)
clears 10 GiB with more than 2 GiB of margin. **Shipped `memoryLimit` set to 10 GiB**
(operator-approved). The RAM-tight knob documented in the README: set
`VLLM_CPU_KVCACHE_SPACE=2` and lower the app's memory in Resources; that trade belongs to
the installer, not the default. An earlier since-boot reading (7.45 GiB peak) is
consistent with these figures.

## Gate 3 evidence (2026-07-30, digest 254b0295)

Restore leg, real backup and real in-place restore:

| Invariant | Proof |
|---|---|
| secret sha256 | `9c3cc4d7bc4da270` identical before and after restore |
| secret mode | 600 cloudron:cloudron post-restore, re-asserted by the boot path |
| boot path | `existing API key found` branch observed post-restore |
| backup weight | app data 16K; the 1.5G model cache (59 files) excluded from the backup as designed; backup task completed in seconds, clean |
| recovery | ready ~135 s after restore |

**Divergence from prediction, recorded as a finding:** the prediction said `/var/lib/vllm`
would come back empty and trigger a re-download. In fact an **in-place restore keeps the
persistentDir intact** (59 files, 1.5G, unchanged), so restores do not pay the re-download.
The empty-start case applies to clones and new-location installs; the re-download path
itself is proven by the fresh-install cycle earlier the same day (fresh install reached
ready unattended with an empty cache).

**Update leg, deferred with reason:** this instance is installed by `--image`, where
`cloudron update --image` is inert (verified in a sibling package's ADR: no image pull
fires; reinstall is the deploy path). The genuine update path for consumers is the
versions-url channel. **Cold-install component proven at publish time (2026-07-30):**
`cloudron install --versions-url <raw CloudronVersions.json>` on a throwaway location
installed 0.1.0 and answered `/health` and `/` with 200, then was torn down. The
update-to-a-new-entry component gets its proof at the first 0.1.x release, when two
entries exist.

The detailed tables below are from the first ladder run (digest `1924e833…`, before the
persistentDirs move); the rerun evidence above supersedes their digest references, the
recipes remain valid.

## Gate 0 evidence (2026-07-30)

| Invariant | Proof |
|---|---|
| digest | box `docker inspect` RepoDigests == registry digest, both `1924e833ef88…` |
| install | `cloudron install --image <digest>` completed; health check green in seconds while the model still downloaded behind the nginx shim (by design, ADR 0003) |
| health | `/health` 200 and landing page 200 from outside during first boot; `/ready` 502 during model download, then 200 |
| logs | zero error-class lines over a 3-minute idle window (grep for error/traceback/EACCES/denied/restart, excluding the expected `/ready` 502 upstream lines during warmup) |
| secrets | `/app/data/.secrets/keys.env` mode 600 `cloudron:cloudron`; sha256 prefix `42de315a639f1393` identical before and after `cloudron restart`; boot log shows `existing API key found` branch |
| first-run | model downloaded once into the persistent cache; post-restart boot reached `/ready` in ~320 s with no re-download (engine re-init dominates on AVX2-class CPU); container `restarts=0` throughout |

Recipe: install by digest, curl `/health` `/ready` `/` from outside, `docker exec` stat +
sha256sum the key, one `cloudron restart`, re-hash, grep the boot branch, poll `/ready`.

## Gate 1 evidence (2026-07-30)

API-key-only architecture (no SSO capability; `optionalSso: true`, no `proxyAuth`), so the
gate is the key-boundary proof. All requests from outside the box against the ladder digest.

| Invariant | Proof |
|---|---|
| public paths | `/health` `/ready` `/ping` `/metrics` `/` all 200 with no key, zero redirects |
| protected paths | `/v1/models` and `/v1/chat/completions` 401 bare; 401 with a wrong key |
| right key | `/v1/models` 200, returns the served model id |
| architecture | zero redirects anywhere: no accidental proxyAuth in the path |

Observation recorded as a decision, not a defect: `/metrics` (Prometheus) is open because
upstream guards only `/v1*`. It exposes usage counters and the model name, no secrets;
left open for scrape simplicity and documented in ADR 0005 and the README. Fence it in
nginx if a future operator objection arrives.
