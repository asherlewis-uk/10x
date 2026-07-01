# UI Reassertion Next Prompt — UI Pass 01

Execute UI Pass 01 of the 11x UI Reassertion Plan.

Context:
- You are inside `/Users/asherlewis/PROJECTS/10x`.
- The runtime reseat from 10x to 11x is already complete (see `FINAL_RESEAT_REPORT.md`).
- The UI still reflects 10x SaaS/product assumptions and must be reasserted as a deliberate local-first cockpit.
- Read `UI_REASSERTION_PLAN.md` first. Then begin this pass.

Pass goal:
No UI changes. Create a complete inventory of visible copy and surfaces that still reflect 10x/SaaS/debug assumptions.

Allowed files/surfaces to inspect (read-only):
- All `10x-macos/Views/**/*.swift`
- `10x-macos/ContentView.swift`
- `10x-macos/Theme.swift`
- `10x-macos/Models/AppTab.swift`
- `10x-macos/Views/Settings/*.swift`
- `10x-macos/Views/Preview/*.swift`
- `10x-macos/Views/Onboarding/*.swift`
- `10x-macos/Views/Auth/*.swift`

Explicit non-goals:
- Do not change any source code.
- Do not make any visual changes.
- Do not change architecture, provider logic, or persistence logic.
- Do not reintroduce Supabase, Superwall, billing, credits, paywalls, hosted deploy, App Store submission automation, or vendor services.
- Do not push.

Deliverable:
Create `UI_SURFACE_AUDIT.md` with the following structure:

```markdown
# 11x UI Surface Audit — Pass 01

## Inventory Method
List the exact grep searches and file inspections performed.

## Banned Phrase Hits
For each banned product phrase from `UI_REASSERTION_PLAN.md`, list every file/line where it appears in primary UI source, with proposed action (keep/remove/rename/reframe).

## Surface-by-Surface Classification
Classify each visible surface as keep / redesign / remove / rename / collapse / move to diagnostics / localize/reframe.
Include: Home, Prompt composer, Project list, Sidebar/window chrome, Settings, Provider settings, Usage/Diagnostics, Builder, Preview, Review, Production, Backend, Environment variables, Onboarding, Login/local profile, Empty states, Error states, Badges/status chips, Copy tone, Icons/branding, Color/accent system, Spacing/layout density.

## Component Inventory
List components to redesign or normalize with file locations and proposed changes.

## Risk Notes
Highlight any rename risks (e.g., AppTab.account), color change blast radius, or files currently allowlisted by `scripts/forbidden-audit`.

## Recommended Pass 02 Scope
Summarize the smallest safe set of files for UI Pass 02.
```

Verification:
- Run `git diff --check` and confirm no changes.
- Run `./scripts/forbidden-audit` and confirm it still passes.
- Run `xcrun swift test` and confirm it still passes.

Commit:
If the audit is complete and verification passes, commit with:
```
docs(ui): inventory visible surfaces for 11x UI reassertion
```

Do not push.
