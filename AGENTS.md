# AGENTS.md

## Project Context

This repository is a fork of the original 10x source. The active product target is 11x, an unlimited single-user local cockpit.

Authoritative current context starts here:

- `README_11X_INIT_CONTEXT.md`
- `docs/10x-local-cockpit/00_MASTER_E2E_RESEAT_PLAN.md`
- `docs/10x-local-cockpit/01_AGENT_EXECUTION_PROMPT.md`
- `docs/10x-local-cockpit/16_LOCAL_IMPLEMENTATION_DEFAULTS.md`

Historical 10x-era docs live under `docs/archive/`. Treat archived docs as reference only, never as current scope.

## Locked Product Identity

- App name: `11x`
- Bundle ID: `app.kasey.11x`
- URL scheme: `elevenx`
- Owned domain for optional Universal Links: `asherlewis.online`
- Optional Universal Link prefix: `/11x/`

The downloaded vendor DMG is a reference artifact only. Do not modify, unpack, patch, resign, overwrite, depend on, or otherwise operate on it.

## Hard Scope Locks

- Remove Supabase entirely as a runtime dependency.
- Remove Superwall entirely.
- Remove billing, pricing, credits, paywalls, checkout, receipt validation, and StoreKit purchase flows.
- Replace hosted vendor deploy with local folder and zip export.
- Replace Supabase persistence with SQL, defaulting to SQLite in the app support directory.
- Replace hosted asset storage with local filesystem storage under app support.
- Keep provider access OpenAI-compatible with BYOK or local gateway support.
- Use `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL` as provider configuration keys.
- Store provider secrets in Keychain first, backend-only encrypted config second, and environment variables only as a development fallback.
- Keep usage tracking local diagnostics only, never gating.

Do not ask whether to keep Supabase, Superwall, pricing, billing, hosted deploy, vendor auth, vendor backend, or vendor updater behavior. The current docs have already decided those removals.

## Working Rules

- Work pass-by-pass from `docs/10x-local-cockpit/00_MASTER_E2E_RESEAT_PLAN.md`.
- If executing the reseat, start with inventory and write or update `AUDIT_LOCALIZATION.md`.
- Keep changes narrowly scoped to the current pass.
- Preserve existing user changes and untracked files.
- Do not push.
- Commits are allowed only after a pass-specific verification succeeds and `git status` has been reviewed.
- Before release, run a forbidden-string audit for active runtime references to Supabase, Superwall, credits, paywalls, billing, vendor hosted deploy, vendor auth, and vendor updater feeds.

## Repository Shape

- SwiftPM manifest: `Package.swift`
- macOS app project: `10x-macos.xcodeproj`
- Main app source: `10x-macos/`
- App tests: `10x-macosTests/`
- Eval runner source: `10x-evals/`
- Eval tests: `10x-evalsTests/`
- Eval suites: `evals/`
- Release scripts and hosted download-site templates: `scripts/release/`

Current source still contains 10x-era identity, Supabase, Superwall, Sparkle/updater, hosted release, and marketing surfaces. Treat those as migration targets, not desired final state.

## Useful Commands

Build the macOS app without signing:

```bash
xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO
```

Run SwiftPM tests:

```bash
swift test
```

Build the eval runner:

```bash
./scripts/evals build
```

Run the smoke eval suite:

```bash
./scripts/evals smoke
```

Release scripts under `scripts/release/` may require signing, notarization, Sparkle, or hosted distribution credentials. Do not treat them as default local proof commands during the 11x reseat unless the current pass specifically targets release packaging.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **10x** (10498 symbols, 43355 relationships, 300 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/10x/context` | Codebase overview, check index freshness |
| `gitnexus://repo/10x/clusters` | All functional areas |
| `gitnexus://repo/10x/processes` | All execution flows |
| `gitnexus://repo/10x/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
