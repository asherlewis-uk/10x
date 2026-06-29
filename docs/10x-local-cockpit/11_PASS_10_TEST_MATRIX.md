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
