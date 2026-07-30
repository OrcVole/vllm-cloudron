# Packaging notes (verified-versus-assumed log, newest first)

Anonymised. Box-specific detail lives in the maintainer's local notes, not here.

---

## 2026-07-30: Dockerfile, local build and smoke proof (Phase 2)

The two-stage build landed and the runtime smoke suite passed locally (rootless podman on an
AVX-512 workstation). Image 5.62 GB uncompressed. Build gate: torch `2.13.0+cpu`,
`cuda.is_available()` False, `import vllm` clean on the base.

**Validated (decisions that held up):**

- **The immediate-health arrangement (ADR 0003).** `/health` answered 200 within 15 seconds
  of container start while the engine was still initialising; `/ready` flipped to 200 at
  roughly 60 seconds with a warm model cache; a single streamed chat completion produced 34
  SSE chunks and terminated with `[DONE]`; `/v1/models` returned 401 bare and 200 keyed.
- **Cache redirection (ADR 0004).** vLLM's torch AOT compile cache demonstrably landed under
  `VLLM_CACHE_ROOT` on the persistent path, and the Hugging Face download went to `HF_HOME`.
- **Thread binding.** Upstream's `auto` binding worked in an unprivileged rootless container
  without `SYS_NICE`; the `numa_migrate_pages` warning it prints is non-fatal.

**Surfaced (things that were wrong or missing, and are now fixed):**

- **uv cannot install the release CPU wheel.** The wheel's exact `setuptools` pin is
  unsatisfiable for uv's first-index strategy against the PyTorch CPU extra index; plain pip
  resolves it. The Dockerfile uses pip for that one step and says why.
- **`VLLM_*` is a reserved environment namespace.** vLLM warns about every unknown
  `VLLM_`-prefixed variable at boot, so all package-defined settings moved to an `LLM_`
  prefix; only genuine upstream variables keep the `VLLM_` names.
- **A model's declared context can abort engine start.** The 0.6B default model declares a
  40960-token context, which alone needs 4.38 GiB of KV cache against the 4 GiB CPU default,
  and the engine refuses to start (exact upstream ValueError recorded in the maintainer
  notes). The package now defaults `--max-model-len` to 8192 and documents raising it
  together with `VLLM_CPU_KVCACHE_SPACE`.
- **The smoke script destroyed its own evidence.** On failure it removed the crashed
  container before the logs were readable; it now keeps the container and detects container
  death during the readiness wait instead of polling a corpse to timeout.
- **A multi-gigabyte ML image redefines secret-scanner noise.** Upstream library source
  matches credential shapes (an embedded base64 font in PIL, the literal private-key header
  constant in the cryptography package's SSH parser), so the scanner gained a by-exact-path
  allowlist that prints every use, in the same visible style as the pinned base-image host
  keys. Separately, bare dictionary words in the maintainer's local denylist false-positive
  against data files that ship inside ML images (tokenizer vocabularies, inflection word
  lists), so denylist patterns must be anchored domain forms, never bare nouns.

**Still open:**

- **AVX2-only hosts are unproven.** The local proof ran on AVX-512 hardware; whether the
  prebuilt `+cpu` wheel runs, and how it performs, on an AVX2-only host is unverified until
  the box gate. Mitigation ladder if it fails: source-build targeting AVX2, or venv copy from
  the upstream CPU image (ADR 0002).
- Carry-overs from recon: `persistentDirs` restore semantics (Gate 3), the exact readiness
  endpoint surface in the pinned version, upstream integrations-listing process.

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
