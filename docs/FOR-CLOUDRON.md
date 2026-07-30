# Notes for the Cloudron team

Observations from packaging vLLM, offered constructively. Everything here was verified on
a real Cloudron 10 box during this package's acceptance gates; nothing is speculation.
The same points appear in compressed form in the forum announcement.

## 1. GPU passthrough is now a platform decision, not an ecosystem blocker

Every AI package on the platform (the official Ollama app included) is CPU-only because
apps cannot reach a GPU. The historical objection was NVIDIA's patched Docker runtime;
that objection no longer holds. Docker has shipped the Container Device Interface
natively since 25.x and enables it by default in the 28.x series that Cloudron 9/10
already runs: the host generates a CDI spec with nvidia-container-toolkit, and a
container requests a named device with no forked daemon involved. The manifest already
has the right vocabulary for this in `capabilities` (`vaapi` mounts `/dev/dri` today);
a `gpu` capability behind a per-app admin toggle would extend an existing pattern rather
than invent one. The support-burden concern is real but boundable: detect rather than
manage the host driver, no-op when no CDI spec exists, start NVIDIA-only, label it
experimental. Forum topic 12401 carries a concrete community proposal along these lines.

## 2. A backup-exclusion primitive for reproducible caches

LLM packages hold multi-gigabyte model caches that are fully reproducible from the
network. `persistentDirs` works as the exclusion mechanism (and this package verified
its semantics: content survives updates and in-place restores, a fresh install starts
empty), but it is all-or-nothing per path, is documented as "use with backupCommand"
even when re-download is the correct restore, and requires the packager to move the
cache outside `/app/data`. A first-class "exclude this path from backup, it is cache"
declaration would serve every AI package and be honest about intent.

## 3. The 60 second proxy timeout versus LLM responses

The reverse proxy cuts responses at roughly 60 seconds and is not per-app tunable. A
non-streamed completion on CPU exceeds that routinely; a streamed one resets the window
per token and works indefinitely (verified through the proxy during this package's
gates). A short packaging-docs note saying "LLM-style apps must stream" would save
every future AI packager an afternoon of mystery truncation.

## 4. Small tooling findings

- `cloudron versions add` against a manifest with no `iconUrl` writes `"iconUrl": ""`
  into the manifest and then fails validation on that same field; pre-setting the raw
  URL avoids the loop.
- `cloudron update --app --image <digest>` does not redeploy a manually-installed app
  (no image pull fires); reinstall by digest is the working path. A warning from the
  CLI would prevent silently stale gates.
- The health monitor's real semantics (only 5xx and connection errors count as
  unhealthy; nothing restarts a running container for a failing health check) are
  excellent, and documenting them would spare packagers defensive over-engineering.

## An offer

The maintainer is happy to test experimental GPU/device capability builds on real
hardware and to adjust this package as a reference consumer.
