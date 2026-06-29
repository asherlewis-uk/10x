# Pass 06 — OpenAI-Compatible Provider Reseat

## Goal

Replace vendor-provider assumptions with a user-owned OpenAI-compatible provider adapter.

## Supported Configuration

```text
OPENAI_API_KEY
OPENAI_BASE_URL
OPENAI_MODEL
```

`OPENAI_BASE_URL` must support OpenAI-compatible endpoints such as:

```text
OpenAI
Ollama OpenAI-compatible endpoint
vLLM
OpenRouter
local gateway
other OpenAI-compatible providers
```

## Boundary

Correct:

```text
UI -> local backend/provider adapter -> model provider
```

Forbidden:

```text
UI -> provider with raw secret key exposed
```

## Provider Adapter Requirements

- Secrets stay backend-only or OS keychain-only.
- Frontend never receives raw API keys.
- Base URL is configurable.
- Model is configurable.
- Errors are local setup errors, not credit/paywall errors.
- Provider diagnostics are visible.
- Provider calls can be mocked in tests.
- Streaming behavior is preserved if present.
- Tool/function calling support is preserved if present.
- Request/response logs are local diagnostics only.

## Config Storage

Store provider metadata in SQL:

```text
provider id
provider type
display name
base url
selected model
created_at
updated_at
```

Store secrets in:

```text
OS keychain
or backend-only encrypted secret store
```

Do not store plaintext secrets in frontend localStorage.

## Tests

Add tests proving:

- Custom base URL is accepted.
- Provider adapter does not require vendor API base URL.
- Missing key shows setup error.
- Invalid base URL shows setup error.
- Provider key is not serialized to frontend state.
- Provider call can be mocked.
- Generation path uses local entitlement, not credits.
- No vendor provider endpoint is hardcoded.

## Acceptance Criteria

- BYOK works.
- Local OpenAI-compatible gateway works.
- Provider setup replaces paywall/credit failures.
- No model access depends on vendor account credits.
