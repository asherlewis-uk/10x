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
