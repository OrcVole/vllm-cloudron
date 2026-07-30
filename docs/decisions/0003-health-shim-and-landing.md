# ADR 0003: nginx immediate-health front end and landing page

Status: accepted, 2026-07-30. Execution pending (Phase 3).

## Context

vLLM binds its HTTP port only after model load and engine initialisation complete; on first
boot that includes a multi-hundred-megabyte model download. During that window a health probe
gets connection-refused, not a 503. The platform's install grace is finite, and a container
that never answers its health check during startup is killed and restarted: a first boot that
can never finish. A sibling package hit exactly this with a warmup-bound server, and the
failure only reproduces on a real box, because local container runs do not health-check during
warmup.

Separately, an API-only app that serves a blank page at `/` reads as broken to anyone who
opens the domain.

## Decision

nginx owns the manifest `httpPort` (8000):

- `location = /health` returns 200 immediately, always.
- `location = /` serves a small static landing page: what this is, where the key lives, a
  copy-paste streamed request.
- Everything else proxies to vLLM on `127.0.0.1:8001`, with `proxy_buffering off` and a long
  read timeout so streamed completions flow token by token.
- `error_log stderr` (the keyword form; the `/dev/stderr` path form fails EACCES as the
  unprivileged user and nginx silently never binds).
- Process supervision keeps vLLM's death fatal to the container: nginx answering `/health`
  must never mask a dead backend into permanent fake health.

## Consequences

- First boot survives arbitrarily long model downloads; progress is visible in the logs.
- The platform's health view says "running", not "model ready". The landing page and logs
  carry readiness; clients get connection errors from `/v1` until warmup ends. A future
  refinement can have nginx expose a distinct readiness path proxied to the backend.
- The smoke test must assert `/health` answers 200 while the model is still loading, not only
  after.
