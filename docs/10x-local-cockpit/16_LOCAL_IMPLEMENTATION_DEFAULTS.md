# 16 — Local Implementation Defaults

## Purpose

This file locks the missing local implementation context so an AI agent can execute the local cockpit reseat pack without repeatedly asking for product-direction clarification.

These defaults are authoritative unless direct repo inspection proves one is technically impossible.

## Locked Product Direction

The forked source must become a separate unlimited single-user local cockpit named **11x**.

The downloaded vendor DMG is not modified, patched, unpacked, resigned, overwritten, or depended on. It remains only a reference app.

## Recommended Defaults Summary

```text
App name: 11x
Bundle identifier: app.kasey.11x
Persistence: SQLite
Database location: app support directory
Asset storage: app support directory under assets/
Provider mode: OpenAI-compatible BYOK/local gateway
Provider env keys: OPENAI_API_KEY, OPENAI_BASE_URL, OPENAI_MODEL
Secret storage: OS keychain first, backend-only encrypted config second, env fallback for dev only
Export shape: local folder export + zip export
Git behavior: commit after each passing pass, never push
Supabase: remove entirely
Superwall: remove entirely
Billing/pricing/credits/paywalls: remove entirely
Hosted deploy: replace with local export
App-store/submission flows: remove unless converted to local export-only artifacts
Marketing flows: remove unless converted to local export-only artifacts
Usage logs: local diagnostics only, never gating
URL scheme: elevenx
Owned domain: asherlewis.online
Universal links: optional later, use applinks:asherlewis.online
Universal link route prefix: /11x/
```

---

# 1. App Identity Defaults

## Recommendation

Use:

```text
Display name: 11x
Internal product name: 11x
Bundle identifier: app.kasey.11x
App support directory: 11x
Preferences namespace: app.kasey.11x
Keychain service namespace: app.kasey.11x
Cache namespace: app.kasey.11x
Log namespace: app.kasey.11x
URL scheme: elevenx
Owned domain: asherlewis.online
Associated domain, optional later: applinks:asherlewis.online
Universal link route prefix, optional later: /11x/
Updater: disabled unless replaced with an owned local release channel
```

## Rationale

The app must run beside the vendor DMG without overwriting it, sharing preferences with it, sharing Keychain records with it, or being caught by the same update feed.

`11x` is intentionally distinct from the vendor app while preserving the recognizable product lineage. It should be treated as the local, user-owned cockpit fork, not as a patched copy of the vendor DMG.

Use `elevenx` as the custom URL scheme. Use `asherlewis.online` for Universal Links / Associated Domains later, not as the private app scheme.

## Agent Instructions

- Locate every app identity file before changing identity.
- Change identity in all platform/build files, not just visible UI.
- Add a persistent local-mode badge in the UI.
- Keep the vendor DMG app name and bundle identifier out of the local build.
- Disable updater feeds unless the repo already supports a safe owned local update channel.
- Do not reuse vendor app groups, URL schemes, Keychain services, or preference domains.
- Do not use `asherlewis.online://` as a custom scheme.
- Use `elevenx://` for local/private deep links.
- Use `https://asherlewis.online/11x/...` only if Universal Links are implemented later.

## Required Assertions

Add static or runtime tests proving:

```text
display name != vendor display name
bundle id != vendor bundle id
app support path contains "11x"
keychain namespace contains "app.kasey.11x"
URL scheme is "elevenx" if custom scheme exists
owned domain is only used for universal links, not custom scheme
updater feed is disabled or non-vendor
local-mode badge exists
```

---

# 2. Database Choice Defaults

## Recommendation

Use SQLite by default.

```text
Database engine: SQLite
Database filename: cockpit.sqlite
Database location: app support directory
Migration location: checked-in SQL migrations
Migration table: schema_migrations
Repository boundary: required
```

## Rationale

This is an unlimited single-user local cockpit. SQLite is the correct default because it works offline, does not require Docker or a Postgres service, bundles cleanly with a desktop app, keeps the cockpit self-contained, and avoids replacing one hosted dependency with another operational dependency.

Postgres should only be selected if repo inspection proves SQLite would cause real technical damage.

## When Postgres Is Allowed

The agent may choose Postgres only if one or more of these are true:

```text
existing code depends heavily on Postgres-only JSONB/query semantics
existing migrations are already pure Postgres and too costly to translate safely
repo uses server-side workers requiring concurrent DB access beyond SQLite's practical limits
existing test harness assumes Postgres and SQLite migration would block progress
future networked agent access is already implemented and cannot run against SQLite
```

If Postgres is selected, the agent must write `PERSISTENCE_DECISION.md` explaining why SQLite was rejected.

## SQL Layer Requirements

Create or preserve clear boundaries:

```text
db connection
migration runner
repository layer
transaction helper
test database setup
asset metadata repository
settings repository
project repository
generation/history repository
provider config repository
usage diagnostics repository
```

## Required Tables or Equivalents

After repo inspection, map existing domain objects into SQL. Expected tables include:

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
schema_migrations
```

Do not force unused tables if the repo has different domain names. Preserve repo semantics.

## Required Tests

```text
empty database migrates cleanly
migration version is recorded
project CRUD persists
generation history persists
settings persist
asset metadata persists
local profile persists
app boots with no Supabase env vars
no Supabase runtime import remains
```

---

# 3. Provider Configuration Defaults

## Recommendation

Use an OpenAI-compatible provider adapter with BYOK/local-gateway support.

```text
OPENAI_API_KEY
OPENAI_BASE_URL
OPENAI_MODEL
```

## Default Provider Behavior

```text
If OPENAI_BASE_URL is empty:
  use the official OpenAI-compatible default expected by the provider adapter.

If OPENAI_BASE_URL is set:
  send requests to that OpenAI-compatible endpoint.

If OPENAI_API_KEY is missing:
  show provider setup error, not paywall, credits, or billing error.

If OPENAI_MODEL is missing:
  use repo default only if safe, otherwise ask through local setup UI.
```

## Local Gateway Targets

The adapter must support OpenAI-compatible endpoints such as:

```text
Ollama OpenAI-compatible endpoint
vLLM
OpenRouter
local gateway
OpenAI
other OpenAI-compatible providers
```

## Secret Storage Priority

Use this priority order:

```text
1. OS Keychain, if the repo already has keychain support or it is easy to add safely.
2. Backend-only encrypted local config.
3. Environment variables as development fallback only.
```

## Hard Rules

- Never expose raw provider secrets to frontend bundles.
- Never store plaintext provider secrets in frontend localStorage.
- Never depend on vendor model credits.
- Never call vendor entitlement APIs.
- Never convert missing provider setup into a pricing/credits/paywall screen.
- Keep provider usage logs as local diagnostics only.

## Required Provider UI

Expose:

```text
provider configured / missing
base URL
selected model
key present / missing, without revealing key
last provider error
test connection action, if low-risk
```

## Required Tests

```text
custom base URL is accepted
missing key shows setup error
provider key is not serialized to frontend state
generation uses local entitlement, not credits
provider call can be mocked
no vendor provider endpoint is hardcoded
```

---

# 4. Export Shape Defaults

## Recommendation

Implement both local folder export and zip export.

```text
Primary export: local folder
Secondary export: zip archive
Optional later: git output folder
```

## Export Root

Use a configurable export location, with a safe default under the user's documents or app support export directory.

Recommended structure:

```text
exports/
  <project_slug>-<timestamp>/
    source/
    assets/
    metadata/
    README.md
    manifest.json
```

Zip export should produce the same structure:

```text
<project_slug>-<timestamp>.zip
```

## Required Export Manifest

Each export should include:

```json
{
  "app": "11x",
  "exportVersion": 1,
  "projectId": "...",
  "projectName": "...",
  "createdAt": "...",
  "includesAssets": true,
  "providerMetadataIncluded": true,
  "secretsIncluded": false
}
```

## Hard Rules

- Exports must not include provider secrets.
- Exports must not require vendor hosted deploy.
- Exports must not require credits.
- Exports must not require login.
- Exports must include local assets needed to rebuild/review the project.
- Hosted deployment buttons must become local export actions or be removed.

## Required Tests

```text
folder export works offline
zip export works offline
export includes generated project files
export includes required assets
export excludes secrets
export does not call vendor backend
export is not gated by credits or billing
```

---

# 5. Commit Permission Defaults

## Recommendation

The agent may commit after each passing pass, but must never push.

```text
Commit allowed: yes
Push allowed: no
Branch creation: no, unless repo state requires isolation
Commit cadence: after each pass that passes verification
Commit style: small, pass-scoped commits
```

## Commit Rules

Before each commit:

```text
git status must be reviewed
pass-specific tests must run where available
no unrelated files should be included
generated junk must be excluded
audit docs should be updated
```

Commit message format:

```text
reseat(local): isolate 11x app identity
reseat(entitlements): replace billing gates
reseat(db): migrate supabase to sqlite
reseat(storage): add local asset store
reseat(provider): add openai-compatible adapter
reseat(export): replace hosted deploy with local export
test(local): add cockpit regression coverage
docs(local): final reseat report
```

## Stop Before Commit If

```text
install fails due to private packages
build system cannot be inferred
tests fail for unrelated unknown reasons
repo has uncommitted user changes unrelated to the pass
migration risks data loss and no backup path exists
```

---

# 6. Blocker Policy

The agent should not ask for clarification on product direction.

## Do Not Ask

Do not ask whether to:

```text
remove Supabase
remove Superwall
remove credits
remove pricing
remove billing
remove hosted deploy
use vendor backend
overwrite the DMG
keep app-store submission flows
keep usage-based billing
```

These are already decided.

## Allowed Hard Blocker Questions

The agent may stop only if:

```text
the repo will not install due to missing private packages
source is materially incomplete
required generated files are absent and cannot be recreated
build requires credentials not provided
app identity cannot be located
test/build commands cannot be inferred after repo inspection
SQLite is technically unsafe and Postgres confirmation is required
provider secret storage cannot be made safe without choosing keychain/encrypted config/env
```

When blocked, output:

```text
exact blocker
files inspected
commands run
exact error
smallest thing needed
safest next step
```

---

# 7. Drop-In Agent Prompt

Use this prompt after unzipping the docs into the source root:

```markdown
You are inside my fork of the 10x source repo.

Read the docs in `docs/10x-local-cockpit/` and execute the reseat/replacement plan end-to-end.

Authoritative defaults:
- App name: `11x`
- Bundle identifier: `app.kasey.11x`
- URL scheme: `elevenx`
- Owned domain: `asherlewis.online`
- Universal links: optional later with `applinks:asherlewis.online` and `/11x/` route prefix
- SQL target: SQLite unless repo inspection proves Postgres is required
- Database filename: `cockpit.sqlite`
- Database location: app support directory
- Supabase: remove entirely
- Superwall: remove entirely
- Billing/pricing/credits/paywalls: remove entirely
- Entitlement: unlimited single-user local cockpit
- Hosted deploy/app-store/submission/vendor marketing flows: remove or replace with local export
- Provider: OpenAI-compatible BYOK/local gateway
- Provider config keys: `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`
- Secrets: keychain first, backend-only encrypted config second, env fallback for dev only
- Exports: local folder and zip
- Vendor DMG: do not touch
- Work pass-by-pass
- Commit after each passing pass
- Do not push
- Stop only for hard blockers
- Produce `FINAL_RESEAT_REPORT.md`

Do not ask me to inspect the repo manually. Inspect it yourself.

Start with inventory and write/update `AUDIT_LOCALIZATION.md`.
```

---

# 8. Final Recommendation Verdict

Use these defaults without further clarification:

```text
App identity: 11x / app.kasey.11x
URL scheme: elevenx
Owned domain: asherlewis.online for optional Universal Links only
Database: SQLite
Provider: OpenAI-compatible BYOK/local gateway
Exports: folder + zip
Commits: yes after each passing pass; never push
```
