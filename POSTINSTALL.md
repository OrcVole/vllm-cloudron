This app is an **API server**. The domain serves a small landing page and the OpenAI-compatible
API at `/v1`; there is no web interface to log in to.

**Your API key** was generated on first run. Open a Terminal for this app (the `>_` button) and
run:

```
cat /app/data/.secrets/keys.env
```

Send it as `Authorization: Bearer <key>` with every `/v1` request.

**First boot is slow on purpose:** the default model downloads and loads before the API
answers. Watch the app's Logs for progress. The landing page shows how to make your first
request once the model is ready.

**Change the model** by setting `LLM_MODEL` in the app's Environment section and restarting.
Larger models need a larger memory limit (Resources section) first.
