# AGENTS.md: vLLM Cloudron package working contract

The settled-decisions record for packaging **vLLM** (`vllm`, Apache-2.0) as a Cloudron
community app. Read this before changing anything. Do not relitigate these decisions without a
concrete reason found on a running box. **The box is the authority, not the docs.**

## What this package is

The vLLM OpenAI-compatible inference server (`vllm serve`), CPU backend, serving exactly one
model per install behind a generated bearer key. No database, no queue, no web application:
the only state is the key, operator configuration, and the model weight cache.

Topology, one row per process, all logging to stdout:

| Process | Role | Port (localhost unless noted) |
|---|---|---|
| nginx | immediate `/health`, static landing page at `/`, streaming-safe proxy to vLLM | 8000 (the manifest `httpPort`) |
| vllm serve | the inference server and OpenAI API | 8001 |

State: no Cloudron database addons. `localstorage` only. Model weights are deliberately
treated as reproducible cache, not primary data (ADR 0004).

## Golden rules

1. **Conformance to the Cloudron contract first.** Adapt the application's runtime environment
   only. Never patch vLLM itself.
2. **Pin everything by digest**: the base image and the upstream version. Exactly one build
   argument (`VLLM_VERSION`), mirrored in the manifest as `upstreamVersion`.
3. **Persisted state only in `/app/data`** (and the declared `persistentDirs` path).
   Re-assert ownership and mode on **every** boot, because a restore drifts them.
4. **Fail loud.** Never silently regenerate the API key, and never clobber operator
   configuration.
5. **Code and docs ship together.** ADRs in `docs/decisions/`. The verified-versus-assumed log
   in `docs/PACKAGING-NOTES.md`, newest first. Box-specific working notes stay in gitignored
   `phase-notes/`.
6. **`CMD`, never `ENTRYPOINT`**, because `ENTRYPOINT` breaks Cloudron debug mode. Maintain
   `.dockerignore` as carefully as `.gitignore`.
7. **Open source only.** vLLM has no commercial split; ship it unmodified.
8. **Anonymise before every push.** No box or mirror hostnames, no real emails beyond the
   declared `contactEmail`, no tokens, no internal URLs in any tracked file. `example.com` is
   the placeholder in public docs. `test/secret-scan.sh` is the release gate.
9. **Git hygiene.** No AI co-authorship and no tool-attribution trailers. Commit as the
   maintainer identity, set **repo-local**, because the machine global is a placeholder.
10. **CPU inference is a scarce resource.** Smoke tests and gates make one inference call at a
    time, never a retry loop; a queued storm pegs every core for minutes.

## Locked decisions (Phase 0 and 1, operator-confirmed 2026-07-30)

- **Manifest id:** `io.github.orcvole.vllm`. The repository's `-cloudron` suffix does not enter
  the id. `author` and `packagerName` are `OrcVole`.
- **Registry:** `ghcr.io/orcvole/vllm-cloudron`, pushed public so the box pulls without
  credentials. Tag scheme `<VERSION>-<pkg-rev>`.
- **Repos:** GitHub `OrcVole/vllm-cloudron` is canonical (renamed from mixed case on
  2026-07-30). A private mirror also exists; its URL is maintainer-local and deliberately not
  recorded in tracked files.
- **CPU only** (ADR 0001). The platform offers no GPU passthrough; a CUDA variant is future
  work contingent on the platform, not on this package.
- **Build shape** (ADR 0002): two-stage on `cloudron/base`, builder installs a Python 3.12 venv
  with CPU torch resolved before vLLM's CPU wheels, runtime stage copies the venv only.
- **Health** (ADR 0003): `healthCheckPath = /health`, answered immediately by nginx, because
  vLLM binds its port only after model load and a first-boot download would otherwise be
  killed inside the install grace window.
- **Auth topology** (ADR 0005): no `proxyAuth`, `optionalSso: true`. `/v1` is protected by the
  generated key (upstream guards `/v1*` only); `/health`, `/ping` and the landing page stay
  open.
- **memoryLimit:** measure, do not guess. 8 GiB is the pre-measurement hypothesis for the
  small default model; Gate 4 sets the shipped floor from the measured warmup peak.

## Pinned upstream

- `cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c`
- vLLM `0.26.0` (tag `v0.26.0`, released 2026-07-27), Apache-2.0. Wheel digests recorded at
  build time in the Dockerfile once Phase 2 lands.

## Build shape

Builder stage on `cloudron/base` creates `/app/code/venv` (Python 3.12), installs CPU-only
torch from the PyTorch CPU index first so vLLM's install finds it satisfied, then installs the
pinned vLLM CPU wheels per the upstream CPU installation documentation. Runtime stage copies
the venv only, keeping layer cruft out of the shipped image. Build gates: `import vllm`
succeeds, `torch.__version__` ends `+cpu`, `torch.cuda.is_available()` is False. The build
gate proves linkage, not function; the real gate is a runtime smoke test that completes a
genuine chat completion.

## Secrets

First-run only, idempotent, under `/app/data`, mode 0600, re-asserted on every boot.

| Secret | Shape | Criticality | Notes |
|---|---|---|---|
| `VLLM_API_KEY` | 64 hex chars | seed-once | Integrations hold it; regeneration breaks them. Not data-loss-critical (no data is encrypted with it), but treated as seed-once anyway. |

Proven byte-identical, by sha256, across both an update and a restore (Gate 3). Never record
the value itself, in any file, ever. The digest is the invariant.

## Environment mapping

Translate on every boot. To be verified against `vllm serve --help` for the pinned version
during Phase 2; the table below is the plan.

Package-defined operator settings use the `LLM_` prefix: vLLM owns the `VLLM_*` namespace
and warns about unknown members on every boot (verified 2026-07-30, v0.26.0).

| Application variable | Source or value | Notes |
|---|---|---|
| `VLLM_API_KEY` | generated key from `/app/data/.secrets/keys.env` | env, never argv |
| `HF_HOME` | persistent model cache path | weights and hub state |
| `VLLM_CACHE_ROOT` | persistent cache path | compiled-artifact cache (verified: torch AOT cache lands here) |
| `LLM_MODEL` (package) | operator env or `Qwen/Qwen3-0.6B` | positional model argument |
| `LLM_MAX_MODEL_LEN` (package) | operator env or `8192` | a model's full declared context can exceed the KV budget and abort engine start (verified: Qwen3-0.6B declares 40960, needs 4.38 GiB KV against the 4 GiB default) |
| `VLLM_CPU_KVCACHE_SPACE` | operator env or `4` | GiB budget, upstream variable |
| `VLLM_CPU_OMP_THREADS_BIND` | upstream default `auto` | passed through when set; `auto` verified working rootless without SYS_NICE (NUMA migrate warning is non-fatal) |
| `HF_TOKEN` | operator-set, flows through unchanged | gated models |
| `HF_HUB_DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `VLLM_NO_USAGE_STATS`, `VLLM_DO_NOT_TRACK` | forced on every boot | |

## Backup and restore

The platform backs up `/app/data` (key, configuration) for free. The model cache lives on a
`persistentDirs` path: excluded from backup, survives restarts and updates, starts empty after
a restore or clone, at which point first boot re-downloads the model (ADR 0004; proven in
Gate 3, including the key sha256 invariant). No logical dump is needed because no bundled
store exists.

## Future compatibility

The single bump point is the `VLLM_VERSION` build argument plus `upstreamVersion` and the
changelog. Upstream releases roughly fortnightly; this package tracks minor releases monthly
rather than chasing every tag, and says so publicly. Out of scope with ADR stubs: GPU/CUDA
variant (platform-blocked, ADR 0001), multi-model serving (upstream feature request), and any
router or gateway bundling (belongs in a gateway app, not here).
