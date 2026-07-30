# Packaging notes (verified-versus-assumed log, newest first)

Anonymised. Box-specific detail lives in the maintainer's local notes, not here.

---

## 2026-07-30: recon and scaffold

Recon established viability (see RECON.md in the maintainer's working folder; the public
summary lives in this repository's README and ADRs), the repositories were renamed to
lowercase `vllm-cloudron`, and this scaffold was created. No Dockerfile exists yet; nothing
has run on a box.

**Validated (decisions that held up):**

- **The field is clear.** Searches of the community app store, the Cloudron forum (packaging
  and wishlist), the official package registry, and GitHub on 2026-07-30 found no existing
  vLLM package anywhere; the only hit was this repository's own empty placeholder.
- **CPU packaging is a known shape, not a research project.** Upstream ships prebuilt x86_64
  CPU wheels (since v0.17.0) and an official `vllm/vllm-openai-cpu` image (~1.8 GB compressed
  for amd64, verified via the registry API on 2026-07-30). Python floor 3.10-3.13 matches the
  base image's 3.12.
- **Health behaviour confirmed from upstream sources.** vLLM's API-key middleware guards only
  `/v1*` paths; `/health` and `/ping` answer without auth. `/health` answers only after model
  load and engine initialisation (upstream issue #6073 and its fix history), which confirms
  the immediate-health front end as a requirement, not a precaution.
- **Upstream AI-contribution policy permits disclosed AI assistance** (DCO sign-off, mandatory
  disclosure, no pure-agent PRs). This constrains upstream contributions from this project,
  not the package itself.

**Surfaced (things that were wrong or missing, and are now fixed):**

- **The placeholder repositories were mixed-case (`vLLM-cloudron`).** Container registries
  require lowercase image names and the packaging convention is lowercase throughout; both
  hosts were renamed to `vllm-cloudron` before any content was pushed, so no consumer is
  affected.
- **The upstream media kit declares no explicit licence.** The logo is used unmodified apart
  from proportional resizing, per the kit's usage guidelines, with attribution in `NOTICE`.
  If upstream later adds licence terms to the media kit, revisit.

**Still open:**

- Whether the target host CPU offers AVX512 or only AVX2; decides the performance claims in
  the README. Settled by reading `/proc/cpuinfo` on the box before Phase 2 completes.
- Exact `persistentDirs` semantics against the current platform version, and the observed
  restore behaviour with an empty model cache. Settled in Gate 3. Unverified until then.
- Whether v0.26.0 exposes a distinct readiness endpoint alongside `/health`. Settled by
  reading the pinned version's route table during Phase 2. Unverified.
- The exact vLLM usage-statistics opt-out variables for the pinned version. Unverified.
- Whether the CPU wheel index resolves cleanly under `uv` on `cloudron/base` (the documented
  path) or the fallback venv-copy from the upstream CPU image is needed. Settled by the
  Phase 2 build.

---

## Conventions for this file

- Newest first, so the top of the file is always the current state of knowledge.
- Every claim carries its evidence. "It works" is not an entry; "a 4 MiB upload returned 200
  and the downloaded bytes were sha256-identical" is.
- Distinguish verified from assumed explicitly. An assumption written as a fact is the single
  most expensive thing this document can contain.
- Anything that generalises beyond this application gets harvested into the private field
  guide at the end of the round. This file is the application's record; the field guide is the
  doctrine.
- Gate ladder evidence tables live in `docs/DEBUGGING.md` or the relevant ADR. This file
  records what the gates taught, not the raw runs.
