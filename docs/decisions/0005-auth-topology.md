# ADR 0005: auth topology, no proxyAuth, app-native bearer key

Status: accepted, 2026-07-30.

## Context

vLLM has no user accounts and no login page. Its clients are programs speaking the OpenAI API
with a bearer key. Cloudron's `proxyAuth` puts an SSO wall in front of HTTP paths; a
programmatic client hitting a proxyAuth wall gets a 302 to a login form it cannot complete,
which breaks every integration. Upstream's own auth middleware guards exactly the `/v1*`
paths; `/health` and `/ping` are deliberately open, which is also what the platform health
prober requires.

## Decision

- No `proxyAuth` addon at all. `optionalSso: true`.
- A single API key, generated on first run (`openssl rand -hex 32`), stored at
  `/app/data/.secrets/keys.env` mode 0600, exported to vLLM as an environment variable (never
  argv, which would leak into the process table). Existing keys are never overwritten.
- Open surfaces: `/health`, `/ping`, `/ready`, the landing page at `/`, and `/metrics`
  (upstream guards only `/v1*`; metrics carry usage counters and the model name, no
  secrets, and staying open keeps Prometheus scraping simple; verified in Gate 1).
  Everything under `/v1` requires `Authorization: Bearer <key>`.

## Consequences

- Every OpenAI-compatible client works unchanged with base URL plus key.
- Key rotation is manual (edit the file, restart) and documented; automatic rotation would
  break integrations that hold the key.
- Gate 1 verifies: `/v1/models` without key returns 401, with key returns 200, `/health`
  returns 200 with no credentials, and no path redirects to any login.
