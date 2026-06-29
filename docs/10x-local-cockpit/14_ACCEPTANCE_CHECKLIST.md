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
