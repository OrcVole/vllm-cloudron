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

| Gate | Status | Evidence |
|---|---|---|
| 0 install and first run | PASS 2026-07-30 | see table below |
| 1 auth | PASS 2026-07-30 | see table below |
| 2 functional flows | not run | |
| 3 update and restore | not run | |
| 4 memory | not run | |

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
