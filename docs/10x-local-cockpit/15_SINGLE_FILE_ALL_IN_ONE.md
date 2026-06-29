# File: 00_MASTER_E2E_RESEAT_PLAN.md

# 11x Local Cockpit — Complete E2E Reseat / Replacement Plan

## Objective

Convert the forked 10x source into a separate, unlimited, single-user local cockpit.

The downloaded vendor DMG remains untouched and installed as the reference product. The fork becomes a separate local-first application with its own app identity, persistence layer, model-provider boundary, asset storage, entitlement model, and build/update configuration.

## Non-Negotiable Boundaries

- Do not patch, unpack, resign, overwrite, or mutate the downloaded vendor DMG.
- Do not use the vendor production backend.
- Do not use vendor auth.
- Do not use vendor hosted app URLs.
- Do not use vendor updater feeds.
- Do not use vendor billing, credits, paywall, subscription, receipt, or entitlement servers.
- Do not bypass vendor entitlements.
- Delete or replace monetization and hosted-service assumptions inside the fork.
- Rename the app and change the bundle identifier so it can run beside the vendor app.
- Replace Supabase with plain SQL.
- Replace hosted storage with local filesystem storage.
- Replace cloud realtime with local event/state invalidation.
- Keep OpenAI-compatible provider support through BYOK/local gateway configuration.
- Keep usage tracking only as local diagnostics, never as a gate.
- Add tests proving the fork boots and works without Supabase, Superwall, credits, hosted services, or billing.

## Target Architecture

```text
/Applications/10x.app
  untouched vendor DMG reference

forked source
  renamed app: 11x / 11x Cockpit
  bundle id: app.kasey.11x or equivalent
  local entitlement: unlimited single-user
  persistence: SQLite or Postgres-backed SQL
  assets: local app-support filesystem
  model access: OpenAI-compatible provider adapter
  secrets: OS keychain or backend-only secret store
  deploy/export: local export, zip, or git folder
  updater: disabled or owned release channel
```

## Recommended Database Choice

Use this decision after inventory:

```text
SQLite:
  best for fastest single-user local cockpit
  best for offline-first app state
  best when no concurrent remote workers are required
  best if project artifacts are mostly local files + metadata

Postgres:
  best if existing backend assumes Postgres semantics
  best if code uses JSONB-heavy queries, transactions, queues, or relational constraints
  best if future networked/multi-device agent access is planned
```

Default recommendation: start with SQLite unless the existing codebase already strongly assumes Postgres semantics.

## E2E Passes

1. Inventory and threat model
2. App identity isolation
3. Monetization and entitlement rewrite
4. Supabase removal and SQL migration
5. Local filesystem asset storage
6. OpenAI-compatible provider reseat
7. Hosted/vendor feature removal
8. Marketing/app-store/submission flow removal
9. Local cockpit UX reseat
10. Test matrix and regression coverage
11. Build, audit, and release packaging
12. Final verification and acceptance report

## Forbidden Runtime Dependencies

The final app must not contain active runtime usage of:

```text
Supabase
@supabase/*
Superwall
RevenueCat
Stripe checkout
StoreKit purchase flow
paywall
credits as gating
vendor hosted deploy
vendor app-store submission flow
vendor updater feed
vendor production API base URL
vendor auth endpoint
vendor analytics tied to conversion/billing
```

References may exist only in audit notes, migration notes, or removed-legacy documentation.

## Final Acceptance Criteria

The local cockpit is accepted only when:

- The app has a distinct name and bundle identifier from the vendor DMG.
- The app boots with no Supabase environment variables.
- The app boots with no Superwall configuration.
- The app boots with no vendor backend configuration.
- Project creation works locally.
- Generation history persists locally.
- Assets persist locally.
- Provider configuration supports custom OpenAI-compatible base URLs.
- Secrets are not exposed to the frontend.
- No pricing, credits, paywall, subscription, or checkout UI is reachable.
- Usage logs exist only for local diagnostics.
- Local export works without hosted vendor infrastructure.
- Tests prove the above.
- Build passes.
- Forbidden-string audit passes, excluding documented migration notes.


---

# File: 01_AGENT_EXECUTION_PROMPT.md

# Agent Execution Prompt — 11x Local Cockpit Reseat

You are working inside my forked 10x source repository.

The downloaded vendor DMG is installed separately and must remain untouched. It is only a behavioral/reference artifact. Do not patch it, unpack it, resign it, overwrite it, or depend on it at runtime.

## Goal

Convert this fork into a separate unlimited single-user local cockpit.

This requires a full reseat/replacement of:

- app identity
- entitlement model
- billing/credits/pricing/paywall system
- Supabase persistence/auth/storage/realtime
- OpenAI/provider configuration
- hosted deployment flows
- app-store/submission flows
- marketing/assets tied to SaaS monetization
- usage-based billing
- updater configuration
- tests and verification

## Hard Rules

- No vendor production backend.
- No vendor auth.
- No vendor hosted app URL.
- No vendor updater feed.
- No vendor billing service.
- No Superwall.
- No Supabase runtime dependency.
- No credit gating.
- No pricing UI.
- No checkout flow.
- No receipt validation.
- No StoreKit purchase flow.
- No bypassing vendor entitlements.
- Replace functionality with local equivalents.
- Keep commits small and pass-based.
- Do not push until all verification passes.

## Pass Order

1. Inventory everything.
2. Isolate app identity.
3. Create local unlimited entitlement module.
4. Remove monetization gates.
5. Replace Supabase with SQL.
6. Replace Supabase Storage with local filesystem assets.
7. Replace Supabase Realtime with local state/events.
8. Reseat OpenAI-compatible provider adapter.
9. Remove hosted/vendor deploy/submission/marketing flows.
10. Add local cockpit UX and setup states.
11. Add regression tests.
12. Run final build/audit.
13. Produce final report.

## Final Output Required

At completion, produce:

- files changed
- feature groups removed
- feature groups reseated
- SQL schema/migrations added
- tests added
- commands run
- command results
- forbidden-string audit result
- remaining hard blockers only


---

# File: 02_PASS_01_INVENTORY_AND_AUDIT.md

# Pass 01 — Inventory and Audit

## Goal

Create a complete map of every vendor, hosted, monetization, Supabase, Superwall, app-store, marketing, and usage-gated dependency before changing behavior.

## Required Output

Create:

```text
AUDIT_LOCALIZATION.md
```

The audit must group findings by feature area.

## Search Terms

Run broad searches for:

```text
Superwall
superwall
pricing
price
credits
credit
billing
subscription
paywall
purchase
receipt
StoreKit
RevenueCat
Stripe
checkout
hosted
deploy
publish
submit
submission
app store
App Store
marketing
analytics
telemetry
apiBaseURL
baseURL
Supabase
supabase
@supabase
SUPABASE
anonKey
service_role
service-role
createClient
OpenAI
OPENAI
updater
Sparkle
downloads
feedURL
```

## Suggested Commands

```bash
grep -RInE "Superwall|superwall|pricing|price|credits?|billing|subscription|paywall|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout" . > audit-monetization.txt || true

grep -RInE "Supabase|supabase|@supabase|SUPABASE|anonKey|service_role|service-role|createClient" . > audit-supabase.txt || true

grep -RInE "hosted|deploy|publish|submit|submission|App Store|app-store|marketing|analytics|telemetry" . > audit-hosted-marketing.txt || true

grep -RInE "apiBaseURL|baseURL|OpenAI|OPENAI|updater|Sparkle|downloads|feedURL" . > audit-config-provider-updater.txt || true
```

## AUDIT_LOCALIZATION.md Structure

```markdown
# Audit Localization

## Summary

## App Identity

## Vendor Backend / Hosted URLs

## Supabase Usage

### Auth

### Database

### Storage

### Realtime

### Edge Functions

### Generated Types

### Environment Variables

## Monetization

### Superwall

### Credits

### Pricing UI

### Billing / Subscription

### StoreKit / Receipt Validation

### Stripe / Checkout

## Hosted Capabilities

### Hosted Deploy

### Publishing

### App Store / Submission

### Marketing Assets / Flows

## Provider Integrations

### OpenAI

### Other Providers

### Secret Handling

## Updater

## Analytics / Telemetry

## Test Coverage Found

## Deletion Candidates

## Reseat Candidates

## Hard Unknowns
```

## Acceptance Criteria

- Every suspicious symbol or file is classified.
- No runtime behavior is changed in this pass.
- The audit distinguishes delete, replace, stub, and keep.
- The audit identifies which database option is least risky: SQLite or Postgres.


---

# File: 03_PASS_02_APP_IDENTITY_ISOLATION.md

# Pass 02 — App Identity Isolation

## Goal

Make the forked app unable to collide with the downloaded vendor DMG.

## Required Changes

Change:

```text
Display name
Bundle identifier
App support directory
Preferences namespace
Keychain service namespace
Updater feed
Local storage namespace
Cache namespace
Log directory
Any app group identifiers
Any URL schemes, if needed
```

## Recommended Values

```text
Display name: 11x
Bundle identifier: app.kasey.11x
App support dir: ~/Library/Application Support/11x
Preferences prefix: app.kasey.11x
Keychain service: app.kasey.11x
Updater: disabled
```

## Required UI Signal

Add a visible local/dev indicator:

```text
11x
Single-user cockpit
Local backend
No billing
```

This prevents accidentally mistaking the fork for the vendor DMG.

## Suggested Searches

```bash
grep -RInE "CFBundleIdentifier|PRODUCT_BUNDLE_IDENTIFIER|CFBundleDisplayName|CFBundleName|Bundle Identifier|10x.app|10x" .
```

## Tests

Add tests or static assertions proving:

- Bundle identifier differs from the vendor app.
- App display name differs from the vendor app.
- Keychain namespace differs.
- App support path differs.
- Updater feed is disabled or owned.
- No vendor update URL remains active.

## Acceptance Criteria

- Vendor DMG and local fork can coexist.
- Installing/building the fork does not overwrite `/Applications/10x.app`.
- The local fork has separate storage, cache, preferences, and secrets.


---

# File: 04_PASS_03_LOCAL_ENTITLEMENTS_AND_MONETIZATION_REMOVAL.md

# Pass 03 — Local Entitlements and Monetization Removal

## Goal

Replace pricing, credits, billing, paywall, subscriptions, checkout, receipt validation, and Superwall with a local unlimited single-user entitlement model.

## Design

Create one source of truth:

```text
localEntitlements
```

Example shape:

```ts
export const localEntitlements = {
  mode: "single_user_unlimited",
  billingEnabled: false,
  creditsEnabled: false,
  creditsRemaining: Number.POSITIVE_INFINITY,
  canGenerate: true,
  canExport: true,
  canUseLocalBackend: true,
  canUseHostedVendorBackend: false,
  canUseBilling: false,
  canPurchaseCredits: false,
}
```

## Rules

- Do not fake a paid state.
- Do not bypass vendor servers.
- Do not call vendor entitlement APIs.
- Delete or replace the entitlement boundary inside the fork.
- Usage tracking may remain as diagnostics only.
- Credits may remain only as legacy migration text or deleted terminology.
- Runtime UI must not present pricing, credits, subscriptions, paywalls, checkout, or purchase surfaces.

## Remove Completely

```text
Superwall SDK
paywall screens
pricing screens
credit purchase screens
subscription gates
checkout flows
receipt validation
StoreKit purchase flows
RevenueCat integration
Stripe checkout integration
billing analytics
conversion analytics
credit exhaustion errors
```

## Replace With

```text
local unlimited entitlement
local diagnostics usage log
setup guidance for model provider keys
clear local error states
```

## Suggested Searches

```bash
grep -RInE "Superwall|superwall|paywall|pricing|credits?|billing|subscription|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout" .
```

## Tests

Add tests proving:

- No Superwall import remains.
- No billing SDK import remains.
- No paywall route/screen is reachable.
- No pricing route/screen is reachable.
- No credit exhaustion state can block generation.
- Local entitlement allows generation.
- Local entitlement allows export.
- Usage logs do not gate any feature.
- Billing flags are false.
- Hosted vendor backend entitlement is false.

## Acceptance Criteria

- Generation/export are never blocked by credits.
- No pricing/billing/paywall UI remains in runtime navigation.
- No monetization SDK remains in dependencies.
- Local entitlement is the only feature gate.


---

# File: 05_PASS_04_SUPABASE_TO_SQL_MIGRATION.md

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


---

# File: 06_PASS_05_LOCAL_FILESYSTEM_ASSETS.md

# Pass 05 — Local Filesystem Asset Storage

## Goal

Replace hosted/cloud storage assumptions with local portable asset storage.

## Storage Root

Use the isolated app support directory:

```text
~/Library/Application Support/11x/assets/
```

or equivalent per-platform app support path.

## Directory Shape

Recommended:

```text
assets/
  projects/
    <project_id>/
      uploads/
      generated/
      previews/
      exports/
      logs/
```

## SQL Metadata

Store:

```text
asset_id
project_id
kind
relative_path
mime_type
size_bytes
checksum
created_at
updated_at
deleted_at
```

## Rules

- Never store absolute paths in exportable project metadata unless required.
- Prefer relative paths under app support.
- Prevent path traversal.
- Validate file extension and MIME when applicable.
- Keep project export portable.
- Do not use Supabase buckets.
- Do not call hosted storage APIs.

## Tests

Add tests proving:

- Asset write creates file on disk.
- Asset metadata persists in SQL.
- Asset read resolves only inside storage root.
- Path traversal is rejected.
- Project export includes required assets.
- Deleting a project handles asset cleanup or tombstoning predictably.
- App boots offline with existing assets.

## Acceptance Criteria

- All generated/uploaded assets are local.
- SQL contains metadata, not blobs by default.
- Exports are portable.
- No cloud bucket dependency remains.


---

# File: 07_PASS_06_OPENAI_PROVIDER_RESEAT.md

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


---

# File: 08_PASS_07_HOSTED_VENDOR_FEATURE_REMOVAL.md

# Pass 07 — Hosted Vendor Feature Removal

## Goal

Remove or replace hosted vendor capabilities that depend on vendor infrastructure.

## Remove or Disable

```text
hosted app publishing
vendor deploy backend
vendor project hosting
vendor app download pipeline
vendor public URL generation
billing-backed deployment
credit-backed deployment
vendor account quota checks
vendor hosted dashboard links
```

## Replace With

```text
local export
project zip export
generated source folder
optional git output folder
local preview
manual deploy instructions if already present
```

## UX Rule

If removing a hosted feature would break navigation, replace it with a clear local-mode explanation:

```text
Hosted publishing is not available in 11x.
Use local export instead.
```

Do not leave dead buttons that fail with vendor auth or credits errors.

## Tests

Add tests proving:

- Hosted deploy button is absent or redirected to local export.
- Vendor hosted URL is not required.
- Export works offline.
- Generated project can be saved locally.
- No billing or credit gate controls deploy/export.
- No vendor deploy endpoint remains active.

## Acceptance Criteria

- No vendor-hosted capability is reachable.
- Local export is the replacement path.
- Hosted failures are not part of normal UX.


---

# File: 09_PASS_08_APP_STORE_SUBMISSION_AND_MARKETING_REMOVAL.md

# Pass 08 — App Store Submission and Marketing Flow Removal

## Goal

Remove app-store/submission-related flows and marketing/asset-generation surfaces tied to the vendor SaaS product.

## Remove or Disable

```text
app-store submission flows
store listing generation tied to vendor pipeline
vendor marketing asset generation
vendor screenshot/metadata pipeline
paid launch flows
submission checklists tied to hosted account
vendor app review automation
public marketing pages inside app
conversion screens
upgrade copy
pricing plan comparison copy
```

## Keep Only If Localized

A feature may remain only if converted into a local non-billing tool, such as:

```text
generate local README
generate local icon assets
generate local screenshots
generate local metadata files
export marketing folder locally
```

It must not depend on:

```text
vendor account
vendor hosting
vendor credits
vendor app submission API
vendor billing
```

## Tests

Add tests proving:

- App-store submission routes/screens are gone or local-only.
- Marketing flows do not mention pricing/credits/vendor upgrade.
- Local asset export works without hosted backend.
- No vendor submission endpoint remains active.

## Acceptance Criteria

- The cockpit is not a vendor SaaS submission funnel.
- Any remaining marketing asset tool is local/export-only.


---

# File: 10_PASS_09_LOCAL_COCKPIT_UX_RESEAT.md

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


---

# File: 11_PASS_10_TEST_MATRIX.md

# Pass 10 — E2E Test Matrix

## Goal

Add regression coverage proving the fork is no longer dependent on vendor monetization, Supabase, hosted services, or billing.

## Static Tests

Required checks:

```text
no Superwall runtime import
no Supabase runtime import
no pricing/paywall route
no credit gate controlling generation/export
no vendor updater URL
no vendor hosted deploy endpoint
app bundle id differs from vendor
```

## Unit Tests

Required:

```text
local entitlement always allows generation
local entitlement always allows export
billingEnabled is false
creditsEnabled is false
provider config accepts custom base URL
provider secrets are not serialized to frontend state
SQL migrations apply cleanly
repositories CRUD projects
repositories persist generation history
asset metadata persists
asset path traversal rejected
```

## Integration Tests

Required:

```text
boot app with no Supabase env vars
boot app with no Superwall config
create local profile
create project
run mocked generation
persist generation
reload app
read project/generation from SQL
write asset
read asset metadata
export project zip/folder
```

## E2E Tests

Required user flows:

```text
first launch local setup
configure provider
create first project
generate with mocked provider
view generation history
export locally
quit/reopen/reload
confirm state persists
confirm no login required
confirm no pricing/credits/paywall surfaces appear
```

## Forbidden String Audit

Run:

```bash
grep -RInE "Superwall|superwall|paywall|pricing|credits?|billing|subscription|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout" .
grep -RInE "Supabase|supabase|@supabase|SUPABASE|anonKey|service_role|service-role|createClient" .
grep -RInE "hosted|vendor|deploy|publish|submit|submission|App Store|app-store|analytics|telemetry|Sparkle|downloads.example|apiBaseURL" .
```

Allowed hits must be limited to:

```text
AUDIT_LOCALIZATION.md
migration notes
legacy removal docs
test names asserting absence
```

## Acceptance Criteria

- All required tests pass.
- Forbidden audit has no active runtime violations.
- Final build succeeds.


---

# File: 12_PASS_11_BUILD_AUDIT_RELEASE.md

# Pass 11 — Build, Audit, and Release Packaging

## Goal

Produce a clean local build that can run beside the vendor DMG.

## Required Commands

Adapt to the repo's package manager/build system:

```bash
npm install
npm run typecheck
npm run lint
npm test
npm run build
```

or:

```bash
pnpm install
pnpm typecheck
pnpm lint
pnpm test
pnpm build
```

or equivalent.

## macOS App Checks

After building:

```bash
codesign -dv --verbose=4 path/to/10x-local.app 2>&1 || true
codesign --verify -vvv --deep --strict path/to/10x-local.app || true
spctl -a -vvv -t execute path/to/10x-local.app || true
plutil -p path/to/10x-local.app/Contents/Info.plist
```

## Identity Checks

Verify:

```text
App name is not vendor app name
Bundle ID is not vendor bundle ID
App support directory is isolated
Updater is disabled or owned
Keychain namespace is isolated
```

## Runtime Smoke Test

Verify:

```text
launch app
local mode badge visible
no login required
provider setup visible
project can be created
mock/local generation can run
generation persists after reload
asset writes to local filesystem
local export works
```

## Final Report

Create:

```text
FINAL_RESEAT_REPORT.md
```

Required sections:

```markdown
# Final Reseat Report

## Summary

## Commit List

## Files Changed

## Features Removed

## Features Replaced

## SQL Persistence

## Asset Storage

## Provider Adapter

## Local Entitlements

## UX Changes

## Tests Added

## Commands Run

## Results

## Forbidden Audit Results

## Remaining Hard Blockers

## Known Non-Goals
```

## Acceptance Criteria

- Build is separate from vendor DMG.
- Runtime works offline/local-first.
- Final report is complete.
- No unresolved blocker is hidden.


---

# File: 13_FORBIDDEN_AUDIT_COMMANDS.md

# Forbidden Audit Commands

Run these after each major pass and before final acceptance.

## Monetization / Billing

```bash
grep -RInE "Superwall|superwall|paywall|pricing|credits?|billing|subscription|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout" . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=build
```

## Supabase

```bash
grep -RInE "Supabase|supabase|@supabase|SUPABASE|anonKey|service_role|service-role|createClient" . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=build
```

## Vendor Hosted / Updater / SaaS

```bash
grep -RInE "hosted|vendor|deploy|publish|submit|submission|App Store|app-store|analytics|telemetry|Sparkle|downloads.example|apiBaseURL" . \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=build
```

## Allowed Hits

Only these categories are allowed:

```text
AUDIT_LOCALIZATION.md
FINAL_RESEAT_REPORT.md
migration notes
legacy removal docs
tests asserting absence
comments explaining removed legacy behavior
```

## Active Runtime Violations

Any hit inside active runtime code must be classified as:

```text
delete
replace
stub local-only
test-only
documentation-only
false positive
```

No active violation can remain unresolved before final acceptance.


---

# File: 14_ACCEPTANCE_CHECKLIST.md

# Final Acceptance Checklist

## App Isolation

- [ ] Vendor DMG remains untouched.
- [ ] Local app has distinct display name.
- [ ] Local app has distinct bundle identifier.
- [ ] Local app has distinct app support path.
- [ ] Local app has distinct preferences namespace.
- [ ] Local app has distinct keychain namespace.
- [ ] Updater is disabled or owned.

## Monetization Removed

- [ ] No Superwall runtime dependency.
- [ ] No pricing UI.
- [ ] No credits UI.
- [ ] No paywall UI.
- [ ] No checkout flow.
- [ ] No subscription flow.
- [ ] No receipt validation.
- [ ] No StoreKit purchase flow.
- [ ] No billing SDK.
- [ ] No usage-based gating.

## Local Entitlements

- [ ] Single local entitlement source of truth exists.
- [ ] Generation allowed.
- [ ] Export allowed.
- [ ] Billing disabled.
- [ ] Credits disabled.
- [ ] Hosted vendor backend disabled.
- [ ] Usage logs are diagnostics only.

## Supabase Removed

- [ ] No Supabase runtime dependency.
- [ ] No Supabase frontend client.
- [ ] No Supabase URL/key required.
- [ ] No Supabase auth.
- [ ] No Supabase storage.
- [ ] No Supabase realtime.
- [ ] No Supabase edge functions.
- [ ] SQL migrations are source of truth.

## SQL Persistence

- [ ] Empty DB migrates cleanly.
- [ ] Project CRUD works.
- [ ] Generation history persists.
- [ ] Settings persist.
- [ ] Local profile persists.
- [ ] Migration table/versioning exists.
- [ ] Test DB initialization works.

## Local Assets

- [ ] Assets write to local filesystem.
- [ ] Asset metadata persists in SQL.
- [ ] Path traversal is rejected.
- [ ] Project export includes assets.
- [ ] App works offline with existing assets.

## Provider Adapter

- [ ] OpenAI-compatible adapter exists.
- [ ] Custom base URL supported.
- [ ] Local gateway supported.
- [ ] Provider key is backend/keychain only.
- [ ] Missing key shows setup error.
- [ ] Invalid provider shows setup error.
- [ ] No vendor provider endpoint hardcoded.

## Hosted / App Store / Marketing

- [ ] Vendor hosted deploy removed or disabled.
- [ ] Local export replaces hosted publish.
- [ ] App-store submission flow removed or local-only.
- [ ] Marketing flows removed or local-export only.
- [ ] No vendor hosted URL required.

## UX

- [ ] Local mode badge visible.
- [ ] No login required for first project.
- [ ] Provider setup visible.
- [ ] Database status visible.
- [ ] Asset path/status visible.
- [ ] No billing/credits/paywall copy visible.

## Tests

- [ ] Static forbidden import tests.
- [ ] Local entitlement tests.
- [ ] SQL migration tests.
- [ ] Repository tests.
- [ ] Asset storage tests.
- [ ] Provider adapter tests.
- [ ] First-launch E2E test.
- [ ] Local export E2E test.
- [ ] Reload persistence E2E test.

## Build

- [ ] Install passes.
- [ ] Typecheck passes.
- [ ] Lint passes.
- [ ] Unit tests pass.
- [ ] Integration/E2E tests pass.
- [ ] Build passes.
- [ ] Final forbidden audit passes.
- [ ] FINAL_RESEAT_REPORT.md complete.
