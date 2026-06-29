# Pass 09 — Local Cockpit UX Reseat

## Goal

Make the UI honestly reflect the new product shape: unlimited single-user local cockpit.

## Required UX Changes

Add clear local setup/status surfaces:

```text
Local mode active
Database status
Asset storage path
Provider status
Selected model
Base URL
Key configured / missing
No billing
No credits
No hosted deploy
Local export available
```

## Remove UX Concepts

```text
upgrade
buy credits
remaining credits
pricing plans
subscription state
billing portal
hosted quota
vendor account requirement
paywall interruptions
```

## Required Error States

Replace billing/credit errors with:

```text
missing provider key
invalid provider key
provider base URL unreachable
model not found
local database unavailable
migration failed
asset storage unavailable
export failed
```

## Setup Flow

Recommended setup order:

```text
1. Welcome to 11x
2. Choose persistence: local SQLite/default or configured Postgres
3. Configure provider: OpenAI-compatible endpoint
4. Confirm asset storage location
5. Create first local project
```

## Tests

Add tests proving:

- Local mode badge exists.
- Billing/credit/pricing UI is absent.
- Provider setup is reachable.
- Missing provider key produces setup error.
- Local export path is reachable.
- App can create a first project without login.
- App can reload and preserve project state.

## Acceptance Criteria

- User never sees SaaS monetization concepts.
- User sees local cockpit state clearly.
- First-run setup does not require vendor auth.
