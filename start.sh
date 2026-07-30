#!/bin/bash
#
# Cloudron entrypoint for vLLM (CPU backend).
#
# Runs as root, prepares /app/data, generates and persists a single API key on first run,
# exports the package-forced settings, starts the immediate-health nginx front end, then drops
# to the cloudron user and execs vLLM. Every package-emitted line is prefixed "==>" so logs
# are greppable. See docs/decisions/0003 (health), 0004 (cache layout), 0005 (auth).

set -euo pipefail

CODE=/app/code
DATA=/app/data
VENV="${CODE}/venv"

SECRETS_DIR="${DATA}/.secrets"
KEYS_ENV="${SECRETS_DIR}/keys.env"
# Reproducible caches live on the persistentDirs path (ADR 0004): outside /app/data, so the
# filesystem backup never carries multi-GB weights; survives updates; empty after a restore
# or clone, at which point first boot re-downloads the model.
MODELS_DIR="/var/lib/vllm"
HF_DIR="${MODELS_DIR}/hf"          # HF_HOME: hub cache, token state, downloaded weights
VLLM_CACHE="${MODELS_DIR}/cache"   # VLLM_CACHE_ROOT: compiled-artifact cache
CACHE_DIR="${DATA}/cache"          # XDG cache (small, backed up)

# nginx owns the manifest httpPort and answers /health immediately; vLLM binds its own port
# only after model load (upstream behaviour), which would otherwise restart-loop first boot.
PUBLIC_PORT=8000
VLLM_PORT=8001

# Operator-tunable settings use the LLM_ prefix, NOT VLLM_: vLLM owns the VLLM_* env
# namespace and warns about unknown members on every boot. The two VLLM_CPU_* vars this
# script touches are real upstream variables and keep their names.
MODEL="${LLM_MODEL:-Qwen/Qwen3-0.6B}"
SERVED_NAME="${LLM_SERVED_MODEL_NAME:-${MODEL}}"
# CPU serving has no business defaulting to a model's full context (Qwen3-0.6B declares
# 40960, which alone outgrows the default KV budget and aborts engine start). 8192 is an
# honest CPU default; raise LLM_MAX_MODEL_LEN and VLLM_CPU_KVCACHE_SPACE together.
MAX_LEN="${LLM_MAX_MODEL_LEN:-8192}"

echo "==> [start] vllm ${UPSTREAM_VERSION:-unknown} (cpu) booting"

# 1. Ownership and layout on EVERY boot: a restore drifts ownership and modes, and the
#    persistentDirs mount arrives root-owned.
echo "==> [start] preparing ${DATA} and ${MODELS_DIR} (secrets, model cache, xdg cache)"
mkdir -p "${SECRETS_DIR}" "${HF_DIR}" "${VLLM_CACHE}" "${CACHE_DIR}"
chown -R cloudron:cloudron "${DATA}" "${MODELS_DIR}"
chmod 0700 "${SECRETS_DIR}"

# Defensive cleanup: a pre-release layout kept the cache at /app/data/models. It is
# reproducible data, so reclaim the backup weight if found. No released version ever
# used that path.
if [[ -d "${DATA}/models" ]]; then
  echo "==> [start] removing stale pre-release cache at ${DATA}/models (reproducible; now at ${MODELS_DIR})"
  rm -rf "${DATA}/models"
fi

# nginx scratch under /run (tmpfs; the root filesystem is read-only at runtime).
NGINX_RUN=/run/nginx
mkdir -p "${NGINX_RUN}/body" "${NGINX_RUN}/proxy" "${NGINX_RUN}/fastcgi" "${NGINX_RUN}/uwsgi" "${NGINX_RUN}/scgi"
chown -R cloudron:cloudron "${NGINX_RUN}"

# 2. First run only: generate the API key. Never clobber an existing key; integrations hold it.
if [[ ! -f "${KEYS_ENV}" ]]; then
  echo "==> [start] first run: generating API key"
  GEN_KEY="$(openssl rand -hex 32)"
  ( umask 077; cat > "${KEYS_ENV}" <<EOF
# vLLM API key, generated on first run. Treat as a secret.
# VLLM_API_KEY: send as "Authorization: Bearer <key>" to the /v1 endpoints.
# /health, /ping, /ready and the landing page are open (no key).
VLLM_API_KEY=${GEN_KEY}
EOF
  )
  unset GEN_KEY
  echo "==> [start] API key stored at ${KEYS_ENV}"
else
  echo "==> [start] existing API key found"
fi
# Re-assert mode on every boot: a restore returns keys.env as 0644/root.
chown cloudron:cloudron "${KEYS_ENV}"
chmod 0600 "${KEYS_ENV}"

# 3. Load the key and export the package-forced settings. The key travels as an environment
#    variable (upstream reads VLLM_API_KEY), never argv, so it stays out of the process table.
# shellcheck disable=SC1090,SC1091
set -a; . "${KEYS_ENV}"; set +a
export VLLM_API_KEY

export HF_HOME="${HF_DIR}"
export VLLM_CACHE_ROOT="${VLLM_CACHE}"
export XDG_CACHE_HOME="${CACHE_DIR}"
export HF_HUB_DISABLE_TELEMETRY=1
export DO_NOT_TRACK=1
export VLLM_NO_USAGE_STATS=1
export VLLM_DO_NOT_TRACK=1
# Gated models: the operator sets HF_TOKEN directly in the app environment; it flows
# through to vLLM and huggingface_hub unchanged, so no indirection is needed here.

# 4. Threads, sized to the cgroup CPU allotment rather than the host core count. OMP threads
#    carry real per-thread working memory; unbounded they scale to every host core and blow
#    the memory limit during warmup (field guide gotcha #41).
CPUS="$(nproc 2>/dev/null || echo 2)"
if [[ -r /sys/fs/cgroup/cpu.max ]]; then
  read -r CQ CP < /sys/fs/cgroup/cpu.max || true
  if [[ "${CQ:-max}" != "max" && "${CP:-0}" -gt 0 ]]; then
    C=$(( CQ / CP )); (( C >= 1 )) && CPUS=$C
  fi
fi
THREADS="${LLM_NUM_THREADS:-${CPUS}}"
(( THREADS < 1 )) && THREADS=1
export OMP_NUM_THREADS="${THREADS}"
export MKL_NUM_THREADS="${THREADS}"
# Thread binding: upstream defaults to "auto"; in an unprivileged container without SYS_NICE
# binding can fail, so the operator can set VLLM_CPU_OMP_THREADS_BIND=nobind if boot logs
# complain. Passed through unchanged when set.
[[ -n "${VLLM_CPU_OMP_THREADS_BIND:-}" ]] && export VLLM_CPU_OMP_THREADS_BIND

# KV cache budget in GiB (upstream default 4). Kept explicit so operators see the lever next
# to memoryLimit; raise both together for bigger models or longer contexts.
export VLLM_CPU_KVCACHE_SPACE="${VLLM_CPU_KVCACHE_SPACE:-4}"

# Intel OpenMP preload, as the upstream CPU wheel docs recommend, when the library is present.
IOMP="$(find "${VENV}" -name 'libiomp5.so' -print -quit 2>/dev/null || true)"
if [[ -n "${IOMP}" ]]; then
  export LD_PRELOAD="${IOMP}${LD_PRELOAD:+:${LD_PRELOAD}}"
  echo "==> [start] intel openmp preloaded: ${IOMP}"
fi

# 5. Informational: the cgroup memory limit, and a note if a GPU device is visible. This build
#    is CPU-only by decision (ADR 0001); the note exists so a future platform GPU capability
#    is noticed rather than silently ignored.
if [[ -r /sys/fs/cgroup/memory.max ]]; then
  echo "==> [start] cgroup memory.max=$(cat /sys/fs/cgroup/memory.max) bytes"
fi
if compgen -G '/dev/nvidia*' >/dev/null 2>&1; then
  echo "==> [start] NOTE: NVIDIA device nodes are visible but this is the CPU build (ADR 0001); a GPU package variant would be needed to use them"
fi

# 6. Assemble the serve arguments. --host is explicit because the container HOSTNAME env is
#    the container id and must not be bound; the port must be deterministic for nginx.
ARGS=( serve "${MODEL}" --host 127.0.0.1 --port "${VLLM_PORT}" \
       --served-model-name "${SERVED_NAME}" --max-model-len "${MAX_LEN}" )
[[ -n "${LLM_EXTRA_ARGS:-}" ]] && { read -r -a EXTRA <<< "${LLM_EXTRA_ARGS}"; ARGS+=( "${EXTRA[@]}" ); }

# 7. Report resolved runtime facts (never the key) and hand off.
echo "==> [start] model    : ${MODEL} served as '${SERVED_NAME}', max context ${MAX_LEN}"
echo "==> [start] http     : nginx 0.0.0.0:${PUBLIC_PORT} -> vllm 127.0.0.1:${VLLM_PORT} (/health open from t=0; /ready 200 once the model is loaded)"
echo "==> [start] cache    : hf=${HF_DIR} vllm=${VLLM_CACHE} (persistent, excluded from backup; first boot downloads the model)"
echo "==> [start] threads  : ${THREADS} (omp/mkl), kv cache ${VLLM_CPU_KVCACHE_SPACE} GiB"
echo "==> [start] api key  : $( [[ -s "${KEYS_ENV}" ]] && echo 'present' || echo 'MISSING' )"

# Immediate-health proxy in the background; vLLM execs as the main process (PID 1) so signals
# reach it and its exit stops the container. nginx is a child and dies with it, so the static
# /health can only bridge warmup, never mask a crash.
echo "==> [start] starting nginx health proxy on :${PUBLIC_PORT}"
gosu cloudron:cloudron nginx -c /app/code/nginx.conf &

echo "==> [start] exec vllm serve (model load and warmup happen now; watch these logs)"
exec gosu cloudron:cloudron "${VENV}/bin/vllm" "${ARGS[@]}"
