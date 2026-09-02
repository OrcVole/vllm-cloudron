`<upstream>0.28.0</upstream>

vLLM is a high-throughput inference server for large language models with the most widely
supported OpenAI-compatible API of the self-hosted options. This package runs it as a
Cloudron app: one install serves one model at `https://<location>/v1`, protected by a
generated API key, with weights cached locally and every OpenAI-style client able to connect
unchanged.

This is CPU inference (amd64). It will not match GPU speed and it is not meant to: it gives
integrations, automations and privacy-sensitive workloads a fully self-hosted OpenAI endpoint
on the server you already run. Pair it with a chat frontend, an AI gateway, embeddings and a
vector store to complete a private AI stack on Cloudron.

Unofficial community package. Not affiliated with the vLLM project or Cloudron.
