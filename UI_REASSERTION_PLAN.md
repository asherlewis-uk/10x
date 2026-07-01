# 11x UI Reassertion Plan

## Executive Verdict

The runtime reseat from 10x to 11x is complete: the app builds as `11x.app` with bundle ID `app.kasey.11x`, uses SQLite persistence, local filesystem assets, an OpenAI-compatible BYOK/local-gateway provider adapter, and a single-user unlimited local entitlement. `xcrun swift test` passes, the unsigned Xcode build passes, and the forbidden runtime audit is clean.

However, the user interface still reflects the original 10x SaaS/product assumptions. The app currently feels like a 10x build with disabled SaaS features rather than a deliberate local-first cockpit. Branding, information architecture, copy tone, settings structure, onboarding, builder chrome, and several preview surfaces all need a full product-surface reassertion.

This plan defines the target 11x interface and a pass-by-pass implementation sequence to reach it without touching architecture, provider logic, persistence logic, or reintroducing any forbidden vendor services.

## Current UI Diagnosis

### Home
- **Status:** redesign
- Uses `Image("10XbuilderLogo")` (leftover 10x branding) in the hero.
- Hero copy is generic: "What would you like to build?".
- Sample prompts include "Subscription cost tracker" (billing vocabulary).
- Empty-state logic exists but is framed around project absence, not around local-first building.
- The prompt composer is present but not yet treated as the dominant launchpad surface.
- Onboarding presentation is triggered but the home landing does not yet read as a local cockpit.

### Prompt composer (Home + Builder)
- **Status:** keep + normalize
- Functional in both places.
- Needs consistent dark, strong prompt surface treatment and iOS-app-builder sample suggestions.
- Attachment chips use the current accent; acceptable but should adopt the calmer 11x accent.

### Project list / Recent projects
- **Status:** redesign
- Currently rendered as a grid of project cards.
- Needs to feel like local artifacts: local save state, last-opened, reveal-in-Finder, export action.
- Cards should lose any cloud-record affordances (sync status, hosted badges).

### Sidebar / window chrome
- `ContentView` tabs use `Image("10XbuilderLogo")` for the home tab.
- Account tab uses `person.crop.circle` and is labeled "Account".
- **Status:** rename/collapse — home tab gets an 11x mark, account tab becomes Settings/Profile, not a vendor account.

### Settings
- `SettingsSection` currently has `general`, `provider`, `usage`.
- **Status:** rebuild IA — add `storage`, `diagnostics`, `about`; rename `usage` to `diagnostics` or keep as a Diagnostics subsection.
- `GeneralSettingsView` exposes rows labeled "Billing: Disabled" and "Hosted deploy: Disabled". This is exactly the disabled-SaaS vocabulary the UI must stop using.
- Storage paths are surfaced but could be richer (copy path, reveal in Finder, export path).

### Provider settings
- `ProviderSettingsView` is already mostly correct functionally.
- **Status:** redesign copy + visual treatment
- Current copy repeats "No credits, billing, or subscription are required" inside the provider panel; this belongs at the product level once, not inside provider setup.
- The SecureField is correct (no raw key reveal).
- Needs a first-class, quiet status panel: endpoint, model, key present/missing, test connection.

### Usage diagnostics
- `UsageSettingsView` currently shows four rows of "No X" phrasing: "No billing or credits", "No paywalls or subscriptions", "No hosted vendor backend dependency", "Local usage logs only".
- **Status:** reframe as Diagnostics
- This reads like an audit list, not a product. Convert to a single calm local-mode status plus a diagnostics log area.

### Preview / Review
- `PreviewPanelView` labels review tab correctly as "Review" (already fixed in Pass 09).
- `ReviewView` still centers on App Store submission packet editing and shows "No marketing assets yet" / "Marketing asset generation is not available in 11x".
- **Status:** reframe
- Keep the local artifact editing (icon, description, screenshots, legal drafts) but reframe as "Export-ready review assets", not App Store submission.
- Remove submission-specific publish/draft CTAs and replace with "Export submission packet" / "Open folder" actions.

### Production views
- `ProductionView` is already mostly reframed (local cockpit, SQLite/keychain, user pipeline).
- **Status:** refine
- Tab labels "Docs" and "Checklist" are fine; the intro and flow section are good.
- Replace any remaining submission/publishing language with export-oriented language.

### Backend / Environment views
- `BackendView` still renders a full Supabase backend management UI behind a local-mode banner.
- `EnvironmentVariablesView` still contains extensive Superwall/Supabase integration configuration UI.
- **Status:** collapse/move to diagnostics
- These surfaces should become read-only local environment inspection or move into a "Diagnostics > Compatibility" section.
- Active hosted integration setup UIs must be removed from the primary builder chrome.

### Onboarding / local profile
- `OnboardingView` already has a step-0 local cockpit welcome (added in Pass 09).
- **Status:** refine
- Step 0 is good but can be quieter and more deliberate.
- Remove any remaining "account setup" language. `LoginView` already says "Continue to the local cockpit.".

### Empty states
- **Status:** rewrite
- Empty project state should invite building, not advertise product state.
- Missing provider setup should point to Settings > Provider, not to billing/upgrade.
- Missing assets should offer local export/import, not hosted generation.

### Error states
- `BackendView` says "Sign in again to run a backend repair." — this is 10x-era remote-auth language.
- Provider errors should be setup errors, never paywall/credit errors.
- Missing key / invalid endpoint errors need calm, actionable copy.

### Badges / status chips
- Current `SettingsMetaChip` and local-mode chips are okay but visually noisy.
- **Status:** redesign
- Use calmer green accent, fewer chips, and avoid a dashboard of "disabled" statuses.

### Copy tone
- Still contains: "No credits, billing, or subscription", "Billing: Disabled", "Hosted deploy: Disabled", "Subscription cost tracker", "Sign in again", "marketing assets", "App Store submission generation", backend "Connected" states tied to Supabase.
- **Status:** rewrite comprehensively

### Icons / branding
- `10XbuilderLogo` asset is used in tab bar and home hero.
- **Status:** replace with intentional 11x mark
- Do not create an entirely new visual identity unless simple; the plan is to make 11x feel intentional, not patched.

### Color / accent system
- `Theme.accent` is `#33B93E`, a bright toy green.
- `Theme.swift` still describes itself as "Design tokens for the 10x liquid glass theme".
- **Status:** update tokens
- Move to a calmer green, native macOS density, restrained translucency, strong prompt surface.

### Spacing / layout density
- **Status:** keep with minor cohesion sweep
- Current spacing tokens are reasonable. The main issue is visual noise from cards and badges, not spacing itself.

## Product Design Principles

1. **Local-first by default.** Every primary action assumes local storage, local generation, and local export. No feature should imply a remote backend is the normal path.
2. **Project-first, not account-first.** The user opens a project, not an account. Tabs are projects; settings are about this Mac and this workspace.
3. **Provider-aware, not provider-noisy.** Provider status is visible where it matters (Settings, builder status bar) but never dominates the product surface.
4. **Status visible but not screaming.** Local mode is a calm fact, not a warning banner parade. One local badge and one settings summary are enough.
5. **Exports over hosted publishing.** The climax of the builder flow is local export (folder + zip), not App Store submission or hosted deploy.
6. **Diagnostics available but not dominant.** Usage logs, backend compatibility, and audit details live under Diagnostics, not in the hero or primary builder chrome.
7. **No billing vocabulary.** No "billing", "credits", "upgrade", "plans", "paywall", "subscription", "checkout", "purchase", or "receipt" in visible product copy.
8. **No disabled-SaaS vocabulary.** Avoid "disabled", "not available", "unavailable" as the primary descriptor of 11x. Instead use positive framing: "Local workspace", "Saved on this Mac", "Export locally".
9. **No fake cloud affordances.** No sync status, hosted badges, cloud records, or remote-management CTAs in the primary UI.
10. **Native macOS density and restraint.** Fewer heavy cards, quieter badges, strong hierarchy, native spacing, native translucency where appropriate.
11. **Dark spatial cockpit aesthetic.** Deep surfaces, one calm accent, clear prompt/input surfaces, readable hierarchy.
12. **Prompt-first but with clear project state.** The composer is the hero; project state (files, preview, transcript, export) is always visible but secondary.

## Information Architecture

### Recommended top-level areas

| Area | Purpose |
|------|---------|
| Home / Projects | Launchpad: prompt composer + recent projects + empty state |
| Builder | Active project workspace: prompt/chat, file tree, preview, transcript, export |
| Preview | Live simulator preview of the generated app |
| Review | Local review/export assets: icon, description, screenshots, legal drafts |
| Export | Local folder export and zip export actions and history |
| Settings | General, Provider, Storage, Diagnostics, About |
| Diagnostics | Local logs, usage diagnostics, audit status, recent failures |

### What should not be top-level

- Billing
- Account
- Hosted Pages
- App Store Submission
- Supabase Management
- Superwall Management
- Store/Checkout/Pricing

### Current tab model update

`AppTab` should keep `.project`. The `.account` kind should be renamed to `.settings` and labeled "Settings" with a gear icon. No account concept remains.

## Home Reassertion

### Goal
Transform Home from a generic 10x landing into an intentional 11x project launchpad.

### Requirements
- Home is the launchpad for local projects.
- The main prompt composer is the dominant visual element.
- Recent projects feel like local artifacts, not cloud records.
- Empty state helps the user start building, not advertise product limitations.
- Sample prompts are iOS-app-builder relevant and free of billing vocabulary.
- Branding is intentional 11x, not leftover 10x.
- Remove repeated "no billing" phrasing from the hero area.
- Local mode is present as a calm status, not a warning.

### Specific changes
- Replace `Image("10XbuilderLogo")` in the hero with an 11x wordmark or system-styled "11x" text mark.
- Replace the tab-bar home icon `10XbuilderLogo` with an 11x mark or `house`/`11x` styled symbol.
- Rewrite hero title from "What would you like to build?" to "Build an iOS app locally" or similar.
- Add a calm local-mode subtitle: "Unlimited local generation · Saved on this Mac · BYOK provider".
- Remove "Subscription cost tracker" from sample prompts. Replace with app-builder prompts such as:
  - "AI daily planner"
  - "Habit tracker with streaks"
  - "Pomodoro timer with analytics"
  - "Workout log with PR tracking"
  - "Local recipe organizer"
  - "iOS flashcard app"
- Project cards show: name, last modified, provider status chip (if missing), reveal-in-Finder, export action.
- Empty state: "No projects yet. Describe an app idea above to start building."
- Remove any "Sign in" language from import/resume error paths.

## Builder Reassertion

### Goal
The builder should feel like a local project cockpit, not a remote dashboard.

### Requirements
- Clear current project identity in the tab and title bar.
- Prompt/composer is always reachable.
- File tree is visible and local-first.
- Generation transcript reads as local generation history.
- Preview state is prominent.
- Local save state is communicated subtly (auto-save, local path).
- Provider status only appears where useful (status bar when missing).
- Export path is surfaced clearly.

### Specific changes
- Project tab title uses project name and project seed icon.
- Add a subtle status bar in `BuilderView` showing: provider configured/missing, last saved, export button.
- Rename/reframe any remaining "Account" references to "Settings" or the local profile.
- Keep chat/prompt surfaces but align tone and accent.
- Ensure no billing/credit CTA remains in `ChatInputView` / `ChatPanelView`.

## Settings Reassertion

### Goal
Productize settings so they answer what 11x is, where data lives, and whether generation is ready.

### Recommended sections

| Section | Icon | Answers |
|---------|------|---------|
| General | `gearshape` | What app is this? Where is local data? Is provider configured? What version/build is running? |
| Provider | `network` | Endpoint, model, key present/missing, test connection, no raw key reveal |
| Storage | `internaldrive` | Database path, assets path, export path, copy/reveal buttons |
| Diagnostics | `stethoscope` or `chart.bar` | Local logs, usage diagnostics only, audit status, recent failures |
| About | `info.circle` | 11x identity, local-first fork notice, upstream relationship, license notice |

### Do not use
- Account
- Billing
- Subscription
- Hosted
- Supabase
- Superwall

### General section
- App identity card: "11x — Unlimited single-user local cockpit".
- Single local-mode summary row: "Local workspace · No account required · Saved on this Mac".
- Provider readiness row: endpoint + model or "Provider setup required".
- Version/build rows.
- Remove explicit "Billing: Disabled" and "Hosted deploy: Disabled" rows.

### Provider section
- Status panel: Base URL, Model, API Key present/missing.
- Endpoint editor: Base URL, Model, SecureField for key.
- Save action.
- Calm privacy note: "Provider secrets are stored in the system keychain and never appear in the UI or exports."
- Remove the three-icon bullet list that repeats billing/credits/subscription.

### Storage section (new)
- Database path row with Copy Path and Reveal in Finder.
- Assets path row with Copy Path and Reveal in Finder.
- Export path row with Copy Path, Reveal in Finder, and Change Location (future).

### Diagnostics section
- Renamed from Usage.
- Local diagnostics card: "Usage data is local only and never gates features."
- Optional: recent events, export history, audit status.
- Keep the local-mode status compact.

### About section (new)
- 11x identity: app name, bundle ID, URL scheme.
- Local-first fork notice.
- Relationship to original 10x.
- License/upstream notice and link to `LICENSE`.

## Copy Reassertion

### Banned visible product phrases
Remove from primary UI copy:
- billing disabled
- hosted deploy disabled
- Supabase disabled
- Superwall disabled
- credits
- upgrade
- plans
- paywall
- account required
- sign out
- App Store submission
- hosted pages
- subscription cost tracker
- marketing assets (as a primary label)
- Sign in

### Allowed / recommended phrases
- Local workspace
- Local cockpit
- Unlimited local generation
- Provider configured
- Export locally
- Saved on this Mac
- OpenAI-compatible endpoint
- Local diagnostics
- No account required
- Bring your own model endpoint
- Your own release pipeline
- Review assets (local)

### Tone rules
- Positive framing first. Instead of "No billing" use "Unlimited local generation".
- One local badge is enough; do not repeat the same facts in every panel.
- Provider setup errors are framed as setup, not purchase.
- Empty states invite action, not apologize for missing SaaS features.

## Visual System Reassertion

### Direction
- Dark native macOS cockpit.
- Calm green accent, not toy green.
- Restrained glass/translucency.
- Strong prompt surface.
- Quieter badges.
- Fewer heavy cards.
- Clear hierarchy.
- Intentional 11x mark.
- Avoid debug-dashboard look.
- Avoid generic SaaS dashboard look.

### Token updates
- Update `Theme.swift` description comment to "Design tokens for the 11x local cockpit".
- Accent: shift from `#33B93E` to a calmer green such as `#2E9E3A` or `#3FAE4A`. Keep it visible but less saturated.
- Keep dark surfaces: `surface` `#1C1C1C`, `surfaceInset` `#141414`, `surfaceElevated` tuned to match.
- Keep text hierarchy.
- Add an `accentSecondary` for subtle status tints.
- Deprecate or rename `billingStatusTint` helper; it is 10x-era naming.

### Components
- `SettingsMetaChip`: smaller, calmer, fewer colors.
- `SettingsPanel`: reduce visual weight; consider removing outer stroke or using subtler separators.
- `localNote`: use secondary text and a single accent icon; avoid icon walls.
- `statusRow`: align labels and values clearly; use monospaced paths.

## Component Inventory

| Component | Action | Notes |
|-----------|--------|-------|
| Local status badge | redesign | Calm chip in home/settings; one fact, not a list |
| Prompt composer | normalize | Strong dark input, consistent in Home and Builder |
| Project card | redesign | Local artifact feel; last modified, reveal/export |
| Empty state card | redesign | Action-oriented, no SaaS apology |
| Settings row | keep + refine | Copy path / reveal actions |
| Provider status row | keep + refine | Endpoint, model, key present/missing |
| Storage path row | add | Database, assets, export paths with copy/reveal |
| Export action | redesign | Primary CTA in builder/review; local folder + zip |
| Diagnostic event row | add | For Diagnostics > Logs |
| Sidebar item | refine | Settings sections, not account/billing |
| Preview state | keep | Live preview already good |
| Error banner | rewrite | Setup errors, not billing errors |
| Local-mode note | redesign | One calm note per surface, not four |
| Copy path button | add | Reusable small button for paths |
| Reveal in Finder button | add | Reusable small button for paths |

## Pass-Based Implementation Plan

### UI Pass 01 — Inventory and Copy Audit

**Goal:** No UI changes. Create a complete inventory of visible copy and surfaces that still reflect 10x/SaaS/debug assumptions.

**Allowed files/surfaces:**
- All `10x-macos/Views/**/*.swift`
- `10x-macos/ContentView.swift`
- `10x-macos/Theme.swift`
- `10x-macos/Models/AppTab.swift`
- `10x-macos/Views/Settings/*.swift`
- `10x-macos/Views/Preview/*.swift`
- `10x-macos/Views/Onboarding/*.swift`
- `10x-macos/Views/Auth/*.swift`

**Explicit non-goals:**
- No code changes.
- No visual changes.
- No architecture changes.
- No provider/persistence logic changes.
- No forbidden service reintroduction.

**Tests:**
- None; this is an audit pass.
- Verify with `grep` inventories for banned phrases.

**Verification:**
- `UI_SURFACE_AUDIT.md` is created and lists every file, banned phrase, and proposed action.
- `git diff --check` passes (no changes).
- `./scripts/forbidden-audit` still passes.

**Commit message:**
```
docs(ui): inventory visible surfaces for 11x UI reassertion
```

---

### UI Pass 02 — Design Tokens and Brand Foundation

**Goal:** Update 11x brand constants, accent use, spacing, typography, badges, status chips, and reusable local-mode components.

**Allowed files/surfaces:**
- `10x-macos/Theme.swift`
- `10x-macos/Assets.xcassets/` (only if replacing `10XbuilderLogo` with an 11x mark; do not modify the vendor DMG)
- Shared settings components: `SettingsMetaChip`, `SettingsPanel`, `SettingsInsetRow`, `SettingsPageHeader`, `SettingsPageContainer`
- `LocalStatusBadge` / `LocalModeNote` reusable components (new)

**Explicit non-goals:**
- No view layout changes beyond shared components.
- No feature logic changes.
- Do not add new dependencies.

**Tests:**
- `ThemeTests` or update existing tests to assert accent color value, no `billingStatusTint` in runtime copy, and `Theme` description does not reference 10x.

**Verification:**
- `xcrun swift test` passes.
- `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO` passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
ui(tokens): reassert 11x design tokens and shared components
```

---

### UI Pass 03 — Home and Project Launchpad

**Goal:** Redesign home, prompt composer, suggestions, empty state, and recent projects.

**Allowed files/surfaces:**
- `10x-macos/Views/HomeView.swift`
- `10x-macos/Views/Chat/HomePromptTextEditor.swift` and related composer helpers
- `10x-macos/ContentView.swift` (home tab icon only)
- `10x-macos/Models/AppTab.swift` if needed for icon

**Explicit non-goals:**
- No builder/preview/settings changes.
- No persistence changes.
- No sample project logic changes.

**Tests:**
- Update or add tests in `LocalCockpitUXTests` to assert:
  - Home sample prompts do not include billing vocabulary.
  - Empty state copy invites building.
  - `Image("10XbuilderLogo")` is no longer referenced in Home or ContentView.

**Verification:**
- `xcrun swift test` passes.
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
ui(home): reassert 11x project launchpad
```

---

### UI Pass 04 — Settings IA Rebuild

**Goal:** Rebuild settings into General, Provider, Storage, Diagnostics, About.

**Allowed files/surfaces:**
- `10x-macos/Views/Settings/SettingsView.swift`
- `10x-macos/Views/Settings/GeneralSettingsView.swift`
- `10x-macos/Views/Settings/ProviderSettingsView.swift`
- `10x-macos/Views/Settings/UsageSettingsView.swift` → rename/refactor into `DiagnosticsSettingsView.swift`
- `10x-macos/Views/Settings/StorageSettingsView.swift` (new)
- `10x-macos/Views/Settings/AboutSettingsView.swift` (new)
- `10x-macos/Models/AppTab.swift` (rename `.account` to `.settings`, label to "Settings", icon to gear)

**Explicit non-goals:**
- No backend logic changes.
- No provider repository changes.
- No new Keychain or database features.

**Tests:**
- Update `LocalCockpitUXTests.testSettingsSectionsDoNotIncludeBilling` to assert sections are General, Provider, Storage, Diagnostics, About and that Billing/Account/Subscription/Hosted do not exist.
- Add test that `AppTab.account()` no longer exists or is renamed to `.settings`.

**Verification:**
- `xcrun swift test` passes.
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
ui(settings): rebuild settings IA for 11x local cockpit
```

---

### UI Pass 05 — Builder/Preview/Review Reframe

**Goal:** Reframe builder surfaces around local project generation, preview, review, and export.

**Allowed files/surfaces:**
- `10x-macos/Views/BuilderView.swift`
- `10x-macos/Views/Preview/PreviewPanelView.swift`
- `10x-macos/Views/Preview/ReviewView.swift`
- `10x-macos/Views/Preview/ProductionView.swift`
- `10x-macos/Views/Chat/ChatPanelView.swift` and `ChatInputView.swift` (copy only)

**Explicit non-goals:**
- No generation logic changes.
- No export logic changes.
- No App Store submission model deletion (keep as local artifact).
- No architecture changes.

**Tests:**
- Add/update `LocalCockpitUXTests` to assert no billing/credit CTA remains in chat.
- Add test that `ReviewView` export affordance is visible and hosted publishing language is absent.
- Update `HostedVendorRemovalTests` if copy assertions exist.

**Verification:**
- `xcrun swift test` passes.
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
ui(builder): reframe builder, preview, and review for local export
```

---

### UI Pass 06 — Diagnostics and Usage Reframe

**Goal:** Move debug/audit details into Diagnostics. Keep usage local-only.

**Allowed files/surfaces:**
- `10x-macos/Views/Settings/DiagnosticsSettingsView.swift`
- `10x-macos/Views/Preview/BackendView.swift`
- `10x-macos/Views/Preview/EnvironmentVariablesView.swift`

**Explicit non-goals:**
- Do not delete underlying compatibility code (SupabaseManagementService, SuperwallManagementService) unless already targeted by a cleanup pass.
- Do not change generated-app guidance models.
- No persistence changes.

**Tests:**
- Add tests that Diagnostics section exists and Usage vocabulary is gone from Settings.
- Assert no "Sign in again" language remains in `BackendView`.
- Assert backend/environment views show local-mode disclaimer and no active hosted setup CTAs.

**Verification:**
- `xcrun swift test` passes.
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
ui(diagnostics): reframe usage and backend views as local diagnostics
```

---

### UI Pass 07 — Error and Empty State System

**Goal:** Rewrite missing provider, DB failure, asset failure, export failure, preview failure, and first-run states.

**Allowed files/surfaces:**
- `10x-macos/Views/HomeView.swift` (empty state)
- `10x-macos/Views/Settings/ProviderSettingsView.swift` (provider setup error)
- `10x-macos/Views/Preview/ReviewView.swift` (no assets state)
- `10x-macos/Views/Preview/BackendView.swift` (local-mode banner and error states)
- `10x-macos/Views/Chat/ChatPanelView.swift` (chat error state)
- `10x-macos/Views/Onboarding/OnboardingView.swift` (first-run)
- `10x-macos/Views/Auth/LoginView.swift` (local profile entry)

**Explicit non-goals:**
- No new error model creation.
- No persistence changes.
- No architecture changes.

**Tests:**
- Add `UIErrorCopyTests` or extend `LocalCockpitUXTests` to assert error copy does not contain banned phrases.
- Assert missing provider error points to Settings > Provider.
- Assert first project can still be created without remote login after copy changes.

**Verification:**
- `xcrun swift test` passes.
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
ui(copy): rewrite error and empty states for 11x
```

---

### UI Pass 08 — Visual Cohesion Sweep

**Goal:** Final layout, spacing, typography, iconography, badge, and copy sweep.

**Allowed files/surfaces:**
- All `10x-macos/Views/**/*.swift`
- `10x-macos/ContentView.swift`
- `10x-macos/Theme.swift`
- Any new reusable components from Pass 02

**Explicit non-goals:**
- No feature additions.
- No persistence/provider changes.

**Tests:**
- Visual copy tests should already pass from earlier passes.
- Run full test suite.

**Verification:**
- `xcrun swift test` passes.
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
ui(polish): visual cohesion sweep across 11x surfaces
```

---

### UI Pass 09 — UI Regression Tests

**Goal:** Update/add tests for copy boundaries and key user flows.

**Allowed files/surfaces:**
- `10x-macosTests/LocalCockpitUXTests.swift`
- `10x-macosTests/HostedVendorRemovalTests.swift`
- `10x-macosTests/ProductionGuideTests.swift`
- New `10x-macosTests/UIReassertionCopyTests.swift` (optional)

**Explicit non-goals:**
- No source UI changes except test-only accessors if absolutely necessary.
- No persistence/provider logic changes.

**Tests:**
- No billing/credits/paywall copy is visible in runtime source.
- No hosted deploy CTA is visible.
- No App Store submission CTA is visible.
- No Account/Sign Out language remains unless truly local and renamed.
- Local status is visible but not over-repeated.
- Provider settings hide raw key.
- Local storage paths are visible in the right settings area.
- First project can be created without remote login.
- Export affordance is visible.
- App identity remains 11x/app.kasey.11x/elevenx.

**Verification:**
- `xcrun swift test` passes (target: previous count + new tests).
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `git diff --check` passes.

**Commit message:**
```
test(ui): add UI reassertion regression coverage
```

---

### UI Pass 10 — Final UI Acceptance Report

**Goal:** Create `UI_REASSERTION_REPORT.md` summarizing changes, verification, and remaining cleanup.

**Allowed files/surfaces:**
- `UI_REASSERTION_REPORT.md` (new)

**Explicit non-goals:**
- No source code changes.
- No visual changes.

**Tests:**
- Full suite: `xcrun swift test`.

**Verification:**
- `xcrun swift test` passes.
- Xcode unsigned build passes.
- `./scripts/forbidden-audit` passes.
- `./scripts/forbidden-audit --inventory` reviewed and any new hits classified.
- `git diff --check` passes.

**Commit message:**
```
docs(ui): final 11x UI reassertion report
```

## Testing Requirements

The UI reassertion must be proven by tests and audits:

1. **No billing/credits/paywall copy is visible.** Scan `10x-macos/Views` and `10x-macos/ContentView.swift` for banned phrases.
2. **No hosted deploy CTA is visible.** No "Publish", "Deploy", "Hosted Pages" primary CTAs outside Diagnostics.
3. **No App Store submission CTA is visible.** `ReviewView` and `ProductionView` use export language.
4. **No Account/Sign Out language remains unless truly local and renamed.** `AppTab` and settings use "Settings", not "Account".
5. **Local status is visible but not over-repeated.** One badge in home/settings; Diagnostics contains the detailed audit list.
6. **Provider settings hide raw key.** `SecureField` is used and `ProviderConfig.publicMetadata()` excludes the key.
7. **Local storage paths are visible in the right settings area.** Storage section shows database, assets, and export paths with copy/reveal.
8. **First project can be created without remote login.** Existing `FirstLaunchIntegrationTests` and `LocalCockpitUXTests` cover this.
9. **Export affordance is visible.** Builder and Review surfaces expose "Export folder" / "Export ZIP".
10. **App identity remains 11x/app.kasey.11x/elevenx.** Existing `AppIdentityIsolationTests` cover this.

## Acceptance Criteria

The UI reassertion is complete only when:

- [ ] The app no longer feels like disabled 10x.
- [ ] The local-first model is obvious without sounding like a debug warning.
- [ ] No SaaS monetization language remains in visible product copy.
- [ ] Settings are productized into General, Provider, Storage, Diagnostics, About.
- [ ] Home feels intentional and useful as a project launchpad.
- [ ] Provider setup feels first-class.
- [ ] Export path is clear in builder and review surfaces.
- [ ] Diagnostics are available but not dominant.
- [ ] `xcrun swift test` passes.
- [ ] `./scripts/forbidden-audit` passes.
- [ ] `UI_REASSERTION_REPORT.md` exists.
- [ ] `git diff --check` passes.
- [ ] No push performed.

## Output Required

Create:
- `UI_REASSERTION_PLAN.md` (this file)
- `UI_REASSERTION_NEXT_PROMPT.md` containing the exact prompt to begin UI Pass 01.

## Major UI Risks Identified

1. **Leftover 10x branding.** The `10XbuilderLogo` asset appears in the tab bar and home hero. Replacing it requires either a new asset or a system-styled text mark.
2. **Settings still uses "Usage" and repeats disabled SaaS vocabulary.** The IA rebuild touches several files and tests.
3. **Backend/Environment views still expose active Supabase/Superwall setup UIs.** Reframing them without deleting underlying compatibility code requires careful scope control.
4. **ReviewView still frames around App Store submission.** Keeping local artifact editing while removing submission language is a copy/architecture boundary.
5. **Accent/color change may affect many surfaces.** Pass 02 must be limited to tokens and shared components to avoid a giant diff.
6. **Copy-only changes can break existing tests.** `HostedVendorRemovalTests`, `ProductionGuideTests`, and `LocalCockpitUXTests` may need updates as copy changes.
7. **AppTab.account rename.** This changes Codable tab persistence; ensure decode handles the old kind or that the change is safe.
8. **Forbidden audit allowlist.** Changes to `EnvironmentVariablesView.swift` or `ReviewView.swift` remain allowlisted, so the audit will not catch new copy. Manual copy tests are required.

## Recommended First UI Implementation Pass

Begin with **UI Pass 01 — Inventory and Copy Audit**. It is zero-risk: no code changes, produces `UI_SURFACE_AUDIT.md`, and gives the exact banned-phrase map and surface list needed before any visual work.
