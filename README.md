# vLLM for Cloudron

An unofficial community package that runs the [vLLM](https://github.com/vllm-project/vllm)
OpenAI-compatible inference server as a Cloudron app. One install serves one model over the
standard OpenAI API (`/v1/chat/completions`, `/v1/completions`, `/v1/models`), protected by a
generated bearer key, with model weights cached on the app's own storage.

**Status: pre-release scaffold.** The package is under construction and has not yet passed its
acceptance gates. Nothing below should be relied on until a tagged release exists.

## What this is, and what it is not

- **CPU inference only.** Cloudron does not currently pass GPUs through to app containers, so
  this package runs vLLM's CPU backend (amd64, AVX2 minimum, AVX512 recommended). Expect
  single-digit tokens per second on small models. That is genuinely useful for integrations,
  background automation, and private processing of sensitive text; it is not a snappy chat
  experience. If Cloudron gains GPU support, a CUDA variant of this package becomes possible
  and is tracked in `docs/decisions/0001-cpu-only.md`.
- **One model per install.** vLLM serves a single base model per server process. Install the
  app more than once for more models, or put an AI gateway in front.
- **An API, not a website.** The app's domain serves a small landing page and the OpenAI API.
  Clients are other applications: chat frontends, gateways, editors, scripts.

## Installation

Not yet published. Once released, the package will install from the Cloudron dashboard via
**Add custom app -> Community app** with the `CloudronVersions.json` URL from this repository,
or with the CLI:

```bash
cloudron install \
  --versions-url https://raw.githubusercontent.com/OrcVole/vllm-cloudron/main/CloudronVersions.json \
  --location vllm.example.com
```

## Configuration

Set in the app's **Environment** section (Cloudron dashboard), then restart. Defaults are
chosen so a fresh install works unattended. The definitive list will be settled during
packaging; current plan:

| Variable | Default | Purpose |
|---|---|---|
| `VLLM_MODEL` | a small instruct model | Hugging Face model id to serve |
| `VLLM_SERVED_MODEL_NAME` | the model id | Name reported by `/v1/models` |
| `VLLM_MAX_MODEL_LEN` | model default | Context length cap (memory lever) |
| `VLLM_CPU_KVCACHE_SPACE` | sized to the app's memory limit | KV cache budget in GiB |
| `VLLM_HF_TOKEN` | unset | Hugging Face token for gated models |

The API key is generated once on first run and stored at `/app/data/.secrets/keys.env`. It is
never regenerated automatically; integrations can rely on it surviving updates and restores.

## Using the API

```bash
curl https://vllm.example.com/v1/chat/completions \
  -H "Authorization: Bearer $VLLM_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "<served model name>", "stream": true,
       "messages": [{"role": "user", "content": "Hello"}]}'
```

Any OpenAI-compatible client works: point it at `https://vllm.example.com/v1` with the key.

**Always prefer streaming.** The platform's reverse proxy times out responses at roughly 60
seconds; a streamed response resets that window with every token, a long non-streamed
completion on CPU does not.

## Operational notes

- **First boot** downloads the model before the API answers. The app reports healthy
  immediately (a lightweight front end answers the platform health check) while vLLM loads
  behind it; watch the app logs for download and warmup progress.
- **Model cache and backups:** model weights are reproducible from the network, so the cache
  is planned to live outside the backup set (`persistentDirs`); after a restore or clone the
  first boot re-downloads the model. The API key and configuration are always backed up.
- **Memory:** the shipped `memoryLimit` is sized for the default small model. Larger models
  need a larger limit (weights plus KV cache plus runtime overhead); raise it in the app's
  Resources section before switching models.
- **CPU is a shared resource.** Concurrent heavy requests queue; retry storms from clients
  make everything slower. Configure clients with generous timeouts and no aggressive retries.

## Licence

vLLM is Apache-2.0, shipped unmodified; this packaging is Apache-2.0 as well. See `LICENSE`
and `NOTICE`. Unofficial package: not affiliated with or endorsed by the vLLM project or
Cloudron.
