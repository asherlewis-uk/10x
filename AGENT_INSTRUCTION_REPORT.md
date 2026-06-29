# Agent Instruction Report

Generated: 2026-06-29 03:15:29 CDT

## Summary

This docs-only init records the current 11x reseat instructions and handoff state.

No runtime source was modified. No Pass 01 implementation was performed. No push was performed.

## Files Read

- `AGENTS.md`
- `README_11X_INIT_CONTEXT.md`
- `docs/10x-local-cockpit/00_MASTER_E2E_RESEAT_PLAN.md`
- `docs/10x-local-cockpit/01_AGENT_EXECUTION_PROMPT.md`
- `docs/10x-local-cockpit/02_PASS_01_INVENTORY_AND_AUDIT.md`
- `docs/10x-local-cockpit/13_FORBIDDEN_AUDIT_COMMANDS.md`
- `docs/10x-local-cockpit/16_LOCAL_IMPLEMENTATION_DEFAULTS.md`

Listings and git state inspected:

- Repository file list via `rg --files`
- Current docs list under `docs/10x-local-cockpit/`
- Archived docs list under `docs/archive/`
- `git status --short`
- `git ls-files` for root historical docs and instruction files
- `git diff --name-status` for observed tracked deletions

## Files Created

- `AGENT_INSTRUCTION_REPORT.md`

## Files Archived Or Moved

No files were archived or moved by this report task.

Observed pre-existing worktree archive state:

- `README.md` is deleted from the tracked root location and `docs/archive/README.md` exists.
- `ROADMAP.md` is deleted from the tracked root location and `docs/archive/ROADMAP.md` exists.
- `docs/beta-release.md` is deleted from the tracked docs location and `docs/archive/beta-release.md` exists.
- `ideas.md` is deleted from the tracked root location and `docs/archive/ideas.md` exists.
- `docs/archive/AGENTS.md` exists as archived historical reference.
- `docs/archive/CLAUDE.md` exists as archived historical reference.

## Archived Files Treated As Historical Only

The following files under `docs/archive/` are historical 10x-era references only. They are not current product scope and should not override the 11x local cockpit docs:

- `docs/archive/AGENTS.md`
- `docs/archive/CLAUDE.md`
- `docs/archive/README.md`
- `docs/archive/ROADMAP.md`
- `docs/archive/beta-release.md`
- `docs/archive/ideas.md`

## Current Authoritative Docs

Primary current context starts with:

- `README_11X_INIT_CONTEXT.md`
- `docs/10x-local-cockpit/00_MASTER_E2E_RESEAT_PLAN.md`
- `docs/10x-local-cockpit/01_AGENT_EXECUTION_PROMPT.md`
- `docs/10x-local-cockpit/16_LOCAL_IMPLEMENTATION_DEFAULTS.md`

Current pass-level implementation docs live under:

- `docs/10x-local-cockpit/02_PASS_01_INVENTORY_AND_AUDIT.md`
- `docs/10x-local-cockpit/03_PASS_02_APP_IDENTITY_ISOLATION.md`
- `docs/10x-local-cockpit/04_PASS_03_LOCAL_ENTITLEMENTS_AND_MONETIZATION_REMOVAL.md`
- `docs/10x-local-cockpit/05_PASS_04_SUPABASE_TO_SQL_MIGRATION.md`
- `docs/10x-local-cockpit/06_PASS_05_LOCAL_FILESYSTEM_ASSETS.md`
- `docs/10x-local-cockpit/07_PASS_06_OPENAI_PROVIDER_RESEAT.md`
- `docs/10x-local-cockpit/08_PASS_07_HOSTED_VENDOR_FEATURE_REMOVAL.md`
- `docs/10x-local-cockpit/09_PASS_08_APP_STORE_SUBMISSION_AND_MARKETING_REMOVAL.md`
- `docs/10x-local-cockpit/10_PASS_09_LOCAL_COCKPIT_UX_RESEAT.md`
- `docs/10x-local-cockpit/11_PASS_10_TEST_MATRIX.md`
- `docs/10x-local-cockpit/12_PASS_11_BUILD_AUDIT_RELEASE.md`
- `docs/10x-local-cockpit/13_FORBIDDEN_AUDIT_COMMANDS.md`
- `docs/10x-local-cockpit/14_ACCEPTANCE_CHECKLIST.md`
- `docs/10x-local-cockpit/15_SINGLE_FILE_ALL_IN_ONE.md`

## Scope Decisions Captured

- Active product target: `11x`, an unlimited single-user local cockpit.
- Locked bundle identifier: `app.kasey.11x`.
- Locked custom URL scheme: `elevenx`.
- Owned domain for optional Universal Links: `asherlewis.online`.
- Optional Universal Link prefix: `/11x/`.
- The downloaded vendor DMG is a reference artifact only and must not be modified, unpacked, patched, resigned, overwritten, depended on, or used as a runtime surface.
- Supabase must be removed entirely as a runtime dependency.
- Superwall must be removed entirely.
- Billing, pricing, credits, paywalls, checkout, receipt validation, and StoreKit purchase flows must be removed.
- Hosted vendor deploy must be replaced with local folder and zip export.
- Supabase persistence must be replaced with SQL, defaulting to SQLite in the app support directory unless inventory proves Postgres is technically required.
- Hosted asset storage must be replaced with local filesystem storage under app support.
- Provider access must remain OpenAI-compatible with BYOK or local gateway support.
- Provider configuration keys are `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL`.
- Provider secrets should use Keychain first, backend-only encrypted config second, and environment variables only as a development fallback.
- Usage tracking remains local diagnostics only and must never gate behavior.
- Work proceeds pass-by-pass from the reseat plan.
- Pass 01 is inventory and audit only and should create or update `AUDIT_LOCALIZATION.md`.
- Commits are allowed only after pass-specific verification succeeds and `git status` has been reviewed.
- Pushing is not allowed.

## Conflicts Avoided

- Did not treat archived 10x-era docs as current scope.
- Did not ask whether to keep Supabase, Superwall, billing, hosted deploy, vendor auth, vendor backend, vendor updater behavior, or related monetization features.
- Did not modify runtime source.
- Did not implement Pass 01.
- Did not run release, signing, notarization, Sparkle, or hosted distribution scripts.
- Did not modify, inspect, unpack, patch, resign, overwrite, or depend on the vendor DMG.
- Did not alter existing untracked or deleted worktree files outside this report.
- Did not push.

## Next Implementation Prompt

```markdown
You are inside `/Users/asherlewis/PROJECTS/10x`, the forked 10x source repo.

Execute Pass 01 only: inventory and audit.

Before changing anything, read:

- `AGENTS.md`
- `README_11X_INIT_CONTEXT.md`
- `docs/10x-local-cockpit/00_MASTER_E2E_RESEAT_PLAN.md`
- `docs/10x-local-cockpit/01_AGENT_EXECUTION_PROMPT.md`
- `docs/10x-local-cockpit/02_PASS_01_INVENTORY_AND_AUDIT.md`
- `docs/10x-local-cockpit/16_LOCAL_IMPLEMENTATION_DEFAULTS.md`

Treat all files under `docs/archive/` as historical reference only.

Create or update `AUDIT_LOCALIZATION.md`. Group findings by feature area and classify each suspicious active reference as delete, replace, stub local-only, keep, documentation-only, test-only, or false positive.

Inventory at least:

- app identity
- vendor backend and hosted URLs
- Supabase auth, database, storage, realtime, generated types, and environment variables
- Superwall
- credits, pricing, billing, subscriptions, checkout, StoreKit, receipt validation, and paywalls
- hosted deploy, publishing, app-store submission, and marketing flows
- OpenAI/provider configuration and secret handling
- updater feeds, Sparkle, downloads, analytics, and telemetry
- test coverage already present
- deletion candidates
- reseat candidates
- hard unknowns
- SQLite versus Postgres risk, defaulting to SQLite unless source inspection proves otherwise

Do not modify runtime behavior during Pass 01.
Do not implement Pass 02.
Do not modify, unpack, patch, resign, overwrite, or depend on the vendor DMG.
Do not push.

After the audit, show commands run, summarize command results, and show `git status --short`.
```
