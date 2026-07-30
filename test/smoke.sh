#!/bin/bash
#
# Local runtime smoke test for the vllm-cloudron image (rootless podman).
#
# Proves the things the build gate cannot: nginx answers /health DURING model warmup (the
# restart-loop trap only reproduces under a health prober), auth guards /v1, and a real
# streamed chat completion produces tokens. One inference call only: CPU inference is a
# scarce resource and retry storms are the documented failure mode.
#
# Usage: test/smoke.sh [IMAGE]   (default: vllm-cloudron:dev)
# A persistent data volume keeps the model cache across runs so re-tests do not re-download.

set -euo pipefail
IMAGE="${1:-vllm-cloudron:dev}"
NAME="vllm-smoke"
VOL="vllm-smoke-data"
PORT=18000
READY_TIMEOUT="${SMOKE_READY_TIMEOUT:-900}"   # first run downloads the model

CRI="$(command -v podman || command -v docker)"
# On failure: dump logs (stderr included; vLLM logs there) and KEEP the container for
# post-mortem. Removing it on failure destroyed the evidence once already.
fail() { echo "SMOKE FAIL: $*"; $CRI logs --tail 60 "$NAME" 2>&1 | tail -60 || true; echo "(container $NAME kept for inspection)"; exit 1; }

$CRI rm -f "$NAME" >/dev/null 2>&1 || true
$CRI volume create "$VOL" >/dev/null 2>&1 || true

echo "==> starting $IMAGE as $NAME on :$PORT"
$CRI run -d --name "$NAME" -p "127.0.0.1:${PORT}:8000" -v "$VOL":/app/data \
  --memory 8g "$IMAGE" >/dev/null

# 1. Liveness must answer 200 well before the model is ready (ADR 0003). Give nginx 15s to
#    come up, then require /health while /ready is still failing or just-ready.
ok=""
for _ in $(seq 1 15); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/health" || true)"
  [[ "$code" == "200" ]] && { ok=1; break; }
  sleep 1
done
[[ -n "$ok" ]] || fail "/health did not answer 200 within 15s of container start"
echo "PASS: /health 200 at t<15s (during warmup)"

# 2. Landing page is HTML, not blank.
curl -s "http://127.0.0.1:${PORT}/" | grep -qi "vLLM API server" || fail "landing page missing"
echo "PASS: landing page served at /"

# 3. Wait for readiness (model downloaded + engine up).
echo "==> waiting for /ready (up to ${READY_TIMEOUT}s; first run downloads the model)"
t=0
until [[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/ready" || true)" == "200" ]]; do
  [[ "$($CRI inspect --format '{{.State.Running}}' "$NAME" 2>/dev/null)" == "true" ]] \
    || fail "container exited during warmup (vLLM crashed; see logs above)"
  sleep 5; t=$((t+5))
  (( t % 60 == 0 )) && echo "    ... still warming (${t}s)"
  (( t >= READY_TIMEOUT )) && fail "/ready not 200 after ${READY_TIMEOUT}s"
done
echo "PASS: /ready 200 after ${t}s"

# 4. Auth: /v1/models must 401 without the key and 200 with it.
KEY="$($CRI exec "$NAME" sh -c 'grep ^VLLM_API_KEY /app/data/.secrets/keys.env | cut -d= -f2')"
[[ -n "$KEY" ]] || fail "could not read generated API key"
code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/v1/models")"
[[ "$code" == "401" ]] || fail "/v1/models without key returned $code, expected 401"
MODEL="$(curl -s -H "Authorization: Bearer $KEY" "http://127.0.0.1:${PORT}/v1/models" | jq -r '.data[0].id')"
[[ -n "$MODEL" && "$MODEL" != "null" ]] || fail "/v1/models with key returned no model"
echo "PASS: auth (401 bare, 200 keyed), served model: $MODEL"

# 5. One real streamed completion. Count SSE data lines and check finish.
echo "==> single streamed completion (the one inference call)"
RESP="$(curl -sN --max-time 300 "http://127.0.0.1:${PORT}/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"stream\":true,\"max_tokens\":32,
       \"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: pong\"}]}")"
chunks="$(printf '%s' "$RESP" | grep -c '^data: ' || true)"
printf '%s' "$RESP" | grep -q 'data: \[DONE\]' || fail "stream did not terminate with [DONE] (chunks=$chunks)"
(( chunks >= 3 )) || fail "too few stream chunks ($chunks)"
echo "PASS: streamed completion, $chunks SSE chunks, terminated with [DONE]"

echo "==> all smoke checks passed"
$CRI rm -f "$NAME" >/dev/null 2>&1 || true
echo "(volume $VOL kept for faster re-runs; remove with: $CRI volume rm $VOL)"
