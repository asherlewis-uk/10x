# Persistence Decision — 11x Local Cockpit

## Decision

SQLite is the persistence engine for the 11x local single-user cockpit.

## Rationale

- The app is explicitly single-user and runs offline/local-first.
- SQLite requires no separate service, Docker, or hosted dependency.
- It bundles cleanly with a macOS app and keeps the cockpit self-contained.
- It avoids replacing one hosted dependency (Supabase) with another operational dependency.

## Location

- Database filename: `cockpit.sqlite`
- Database location: `~/Library/Application Support/11x/`
- Migrations: `10x-macos/Services/DB/migrations/`
- Migration tracking table: `schema_migrations`

## What Was Replaced

Supabase auth, database, storage, realtime, and edge-function assumptions were replaced with:

- `CockpitDatabase` — SQLite connection and migration runner
- `ProfileRepository` — single local user profile
- `ProjectRepository` — project metadata
- `VersionRepository` — generation/version history
- `MessageRepository` — message metadata (conversation files still use `LocalProjectStore`)
- `AppSettingsRepository` — key/value settings
- `UsageLogRepository` — local diagnostics-only usage logs
- `AssetRepository` — local asset metadata (files live in app support)

## Postgres Exception

Postgres was not selected. No repo condition required it.
