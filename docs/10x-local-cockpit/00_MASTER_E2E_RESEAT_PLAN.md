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
