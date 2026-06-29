# Pass 04 — Supabase to SQL Migration

## Goal

Remove Supabase entirely and replace it with plain SQL persistence.

## Hard Constraints

- No `@supabase/*` runtime dependency.
- No Supabase URL.
- No Supabase anon key.
- No Supabase service-role key.
- No Supabase hosted project ID.
- No frontend Supabase client.
- No Supabase auth dependency.
- No Supabase storage dependency.
- No Supabase realtime dependency.
- No Supabase edge-function dependency.
- All schema must live in checked-in SQL migrations.
- Runtime must work offline/local-first.

## Database Choice

After inventory, choose either:

```text
SQLite
  recommended for fastest local single-user cockpit

Postgres
  use if existing backend depends on Postgres-specific semantics
```

Document the decision in:

```text
PERSISTENCE_DECISION.md
```

## Required Abstractions

Create or refactor into:

```text
src/db/
src/db/migrations/
src/db/schema/
src/repositories/
src/storage/
```

Names may vary by repo conventions, but boundaries must exist.

## Required Repository Areas

Model these as SQL-backed repositories if present in the app:

```text
local_profile
projects
project_files
generations
generation_steps
assets
provider_configs
provider_key_metadata
usage_logs
app_settings
export_jobs
diagnostic_events
```

## Supabase Auth Replacement

Replace with:

```text
single local user profile
no login required
optional local lock/passcode only if low-risk
no remote session dependency
no token refresh dependency
```

## Supabase Database Replacement

Convert table definitions and access patterns into SQL migrations and repository methods.

Required migration behavior:

- migrate empty DB cleanly
- migrate existing local DB forward
- record applied migration versions
- fail loudly on migration corruption
- allow test DB initialization

## Supabase Storage Replacement

Supabase Storage must become local filesystem storage.

SQL stores metadata only:

```text
asset id
project id
kind
relative path
mime type
size
created_at
updated_at
checksum if useful
```

Files live under the app support directory.

## Supabase Realtime Replacement

Replace with:

```text
local event emitter
state invalidation
repository callbacks
polling only where necessary
```

No cloud websocket dependency.

## RLS Replacement

Supabase row-level security assumptions become local process boundaries:

```text
single-user app
database not directly exposed to network
provider secrets stored outside frontend
filesystem scoped to app support directory
```

## Dependency Removal

Remove:

```text
@supabase/*
supabase client config
Supabase env vars
Supabase generated types
Supabase auth/session helpers
Supabase storage helpers
Supabase realtime helpers
Supabase edge function clients
```

## Tests

Add tests proving:

- App boots with no Supabase env vars.
- No Supabase runtime imports remain.
- Migrations apply on empty DB.
- Project CRUD works through SQL.
- Generation history persists through SQL.
- Settings persist through SQL.
- Asset metadata persists through SQL.
- Asset files exist on disk.
- Local profile loads without remote auth.
- No Supabase URL/key strings remain in active config.

## Acceptance Criteria

- Full app flow works without Supabase.
- SQL migrations are the source of truth.
- Supabase appears only in migration/audit notes, not active runtime code.
