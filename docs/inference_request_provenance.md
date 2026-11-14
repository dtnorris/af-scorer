# Inference request provenance

Every non-preflight scoring call persists the exact provider request description
before model inference begins.

For a target artifact named `dimension_foo`, the raw run directory contains:

- `dimension_foo_request.json` — provider-native request provenance written before inference.
- `dimension_foo.json` — complete raw provider response written after a successful response.
- `run_metadata.json` where the active prompt profile requires run metadata.

The request artifact includes:

- provider and transport/operation;
- exact model request payload;
- full system instructions and user/source prompt;
- exact structured-output schema;
- prompt SHA-256 using the same `instructions + NUL + input` convention as preflight;
- schema SHA-256;
- SHA-256 of the serialized provider request description;
- `recorded_before_inference: true`.

For Ollama, the artifact records the exact OpenAI-compatible
`/v1/chat/completions` endpoint and payload used by the provider. For OpenAI it
records the exact keyword arguments supplied to `responses.create`.

Authorization headers, API keys, and other credentials are never included.

The response artifact remains unchanged, so provider-returned reasoning fields
(such as Ollama `choices[0].message.reasoning`) remain available exactly where
existing forensic tooling expects them.
