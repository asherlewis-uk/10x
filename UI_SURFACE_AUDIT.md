# 11x UI Surface Audit — Pass 01

## Inventory Method

Audit performed by reading `UI_REASSERTION_PLAN.md` first, then running targeted greps over the primary UI source surfaces listed in the plan. No source code was modified.

Exact searches run:

```bash
grep -RInE 'billing disabled|hosted deploy disabled|Supabase disabled|Superwall disabled|credits|upgrade|plans|paywall|account required|sign out|App Store submission|hosted pages|subscription|checkout|purchase|receipt|StoreKit|RevenueCat|Stripe|Sign in|Sign up|Sign out|Account|Billing|Plan|Pricing|Paywall|Subscribe|marketing assets|backend repair|Sign in again|10XbuilderLogo|10x' 10x-macos/Views 10x-macos/ContentView.swift 10x-macos/Theme.swift 10x-macos/Models/AppTab.swift
```

Additional targeted reads of full files:
- `10x-macos/Views/Settings/SettingsView.swift`
- `10x-macos/Views/Settings/GeneralSettingsView.swift`
- `10x-macos/Views/Settings/ProviderSettingsView.swift`
- `10x-macos/Views/Settings/UsageSettingsView.swift`
- `10x-macos/Views/HomeView.swift`
- `10x-macos/Views/ContentView.swift`
- `10x-macos/Views/Auth/LoginView.swift`
- `10x-macos/Views/Onboarding/OnboardingView.swift`
- `10x-macos/Views/Preview/PreviewPanelView.swift`
- `10x-macos/Views/Preview/ReviewView.swift`
- `10x-macos/Views/Preview/ProductionView.swift`
- `10x-macos/Views/Preview/BackendView.swift`
- `10x-macos/Views/Preview/EnvironmentVariablesView.swift`
- `10x-macos/Views/Preview/LivePreviewView.swift`
- `10x-macos/Views/Chat/ChatInputView.swift`
- `10x-macos/Views/Chat/ChatPanelView.swift`
- `10x-macos/Models/AppTab.swift`
- `10x-macos/Theme.swift`

All findings below are scoped to primary UI source (`10x-macos/Views`, `10x-macos/ContentView.swift`, `10x-macos/Theme.swift`, `10x-macos/Models/AppTab.swift`). Generated-app guidance and legacy model code outside these surfaces are not inventoried in this pass.

## Banned Phrase Hits

| Banned phrase / concept | File(s) | Line(s) | Proposed action |
|-------------------------|---------|---------|-----------------|
| "Billing" label in settings | `GeneralSettingsView.swift` | 54 | Remove the explicit "Billing: Disabled" row. Replace with a single positive local-mode summary. |
| "credits, billing, or subscription" | `ProviderSettingsView.swift` | 109 | Remove from provider panel; keep one calm local-mode note in General/Diagnostics only. |
| "No billing or credits" | `UsageSettingsView.swift` | 22 | Reframe Diagnostics section; remove negative list items. |
| "No paywalls or subscriptions" | `UsageSettingsView.swift` | 23 | Reframe Diagnostics section; remove negative list items. |
| "Sign in again to run a backend repair" | `BackendView.swift` | 916 | Rewrite to local-cockpit message (backend repair is not available; use local export). |
| "Sign in to 10x again, then reconnect Supabase" | `EnvironmentVariablesView.swift` | 3820 | Rewrite to local-mode error message; remove 10x-era remote-auth language. |
| "10x" in copy/labels where app identity is meant | `EnvironmentVariablesView.swift` | many | Keep when it refers to the generated app or original upstream, but reframe primary cockpit copy to "11x". |
| "marketing assets" | `ReviewView.swift` | 228, `LivePreviewView.swift` | 325 | Reframe as "review assets" or "export assets". |
| "App Store submission generation is not available in 11x" | `ReviewView.swift` | 250, 536, 570, 908, 952, 1190 | Reframe as "Local review/export assets" — keep editing, remove submission-first language. |
| "Demo Account Checklist" | `ReviewView.swift` | 1067 | Keep but rename to "Demo Profile Checklist" if it describes generated app. |
| "10XbuilderLogo" image asset | `ContentView.swift` | 300; `HomeView.swift` | 145; `LoginView.swift` | 101 | Replace with intentional 11x mark or system-styled text. |
| "Subscription cost tracker" sample prompt | `HomeView.swift` | 68 | Remove; replace with a non-billing iOS app idea. |
| "Account" tab kind/label | `AppTab.swift` | 20; `ContentView.swift` | 421, 508 | Rename `.account` to `.settings`, label to "Settings", icon to gear. |
| "No billing or credits" onboarding bullet | `OnboardingView.swift` | 232 | Reframe to positive local-mode bullet ("Unlimited local generation"). |
| "Stripe" as onboarding design example | `OnboardingView.swift` | 322 | Remove or replace with non-monetization design example. |
| "Design tokens for the 10x liquid glass theme" | `Theme.swift` | 3 | Update comment to 11x local cockpit. |
| "billingStatusTint" | `Theme.swift` | 80+ | Rename/deprecate; it is 10x-era naming. |
| "10x Project" default naming | `EnvironmentVariablesView.swift` | 450 | Keep as generated project default or update to "11x Project". |
| "Supabase" / "Superwall" UI copy and setup CTAs | `EnvironmentVariablesView.swift` | extensive | Move hosted integration setup into Diagnostics/Compatibility or collapse behind local-mode banner. |

## Surface-by-Surface Classification

### Home
- **Status:** redesign
- Leftover `10XbuilderLogo` in hero (line 145).
- Generic hero copy "What would you like to build?".
- Sample prompt "Subscription cost tracker" is billing vocabulary (line 68).
- Empty-state card is already local-cockpit framed (good) but can be more action-oriented.
- Project grid is fine structurally; needs local artifact affordances (reveal/export) in later pass.

### Prompt composer (Home + Builder)
- **Status:** keep + normalize
- Strong dark input surface exists in `HomeView`.
- No banned phrases found in composer copy.
- Needs consistent 11x accent and stronger prompt-first hierarchy.

### Project list / Recent projects
- **Status:** redesign
- `projectCard` uses iPhone mockup aesthetic (good).
- Missing local artifact actions: no reveal-in-Finder or export on card.
- Cards are labeled "iOS App" / "Archived iOS App" (acceptable).

### Sidebar / window chrome
- **Status:** rename/collapse
- `ContentView` home tab uses `Image("10XbuilderLogo")` (line 300).
- Profile/account button opens `openAccountTab()` (lines 421, 508).
- `AppTab.account()` label is "Account" with `person.crop.circle` icon (line 20).
- Target: home tab gets 11x mark, account becomes Settings with gear icon.

### Settings
- **Status:** rebuild IA
- `SettingsSection` has `general`, `provider`, `usage`.
- `GeneralSettingsView` exposes "Billing: Disabled" and "Hosted deploy: Disabled" — disabled-SaaS vocabulary.
- Need sections: General, Provider, Storage, Diagnostics, About.

### Provider settings
- **Status:** redesign copy + visual treatment
- `ProviderSettingsView` repeats billing/credits/subscription note (line 109).
- Functional key handling is correct (SecureField, no raw reveal).
- Needs calmer local-mode note and first-class status panel.

### Usage / Diagnostics
- **Status:** reframe
- `UsageSettingsView` is a list of "No X" negatives.
- Rename to Diagnostics and keep a single positive local-mode summary.

### Builder
- **Status:** keep + refine
- `BuilderView` is just a split view; no changes needed.
- No banned copy in `ChatInputView`/`ChatPanelView` beyond the word "Plan" (which is the project plan, not a pricing plan).
- Builder needs a subtle status bar in later pass for provider/export.

### Preview
- **Status:** keep
- `PreviewPanelView` is well-structured: Preview, Open in Xcode, Open in Finder.
- No banned copy.

### Review
- **Status:** reframe
- Centered on "App Store submission" with repeated "not available in 11x" language.
- Keep local artifact editing (icon, description, screenshots, legal drafts) but reframe as export-ready review assets.
- Remove publish/slug-locked helpers or reframe as local-only metadata.

### Production
- **Status:** refine
- Already reframed to local cockpit / user pipeline in Pass 08.
- No banned copy found in the inspected portion; full file should be scanned in Pass 08.

### Backend
- **Status:** collapse / move to diagnostics
- `BackendView` has a good `localModeBanner` but still renders a full Supabase backend management UI below it.
- "Sign in again to run a backend repair" (line 916) is remote-auth language.
- Should become read-only local environment inspection or move into Diagnostics.

### Environment variables / Integrations
- **Status:** collapse / move to diagnostics
- `EnvironmentVariablesView` is a large Superwall/Supabase integration setup surface (~3800 lines).
- Contains active hosted setup CTAs: Connect Supabase, Connect Superwall, Paywall Setup, Open Paywalls, Refresh Paywalls, etc.
- Contains "Sign in to 10x again, then reconnect Supabase" error copy.
- Should be collapsed into a read-only local environment inspector or moved to Diagnostics > Compatibility.

### Onboarding
- **Status:** refine
- Step 0 local cockpit welcome is good.
- Bullet "No billing or credits" should become positive: "Unlimited local generation".
- Design example includes "Stripe" (line 322) — remove or replace.
- Overall tone is good; needs minor copy sweep.

### Login / local profile
- **Status:** refine
- Uses `10XbuilderLogo` (line 101).
- No explicit banned auth copy found in inspected portion.
- "Continue to the local cockpit" already present from Pass 09.

### Empty states
- **Status:** rewrite
- Home empty state is good but can be more direct: "No projects yet. Describe an app idea above to start building."
- Review empty state says "No marketing assets yet" / "App Store submission generation is not available in 11x" — reframe as local review/export assets.
- LivePreview empty copy "Save screenshots here for reuse in marketing assets" — reframe.

### Error states
- **Status:** rewrite
- `BackendView` "Sign in again to run a backend repair" — rewrite.
- `EnvironmentVariablesView` "Sign in to 10x again, then reconnect Supabase" — rewrite.
- Provider setup errors already direct to Settings (good).

### Badges / status chips
- **Status:** redesign
- `SettingsMetaChip` in provider/usage is okay but visually noisy.
- `projectTabButton` count chips are fine.
- Local-mode badge is not yet visible in Home.

### Copy tone
- **Status:** rewrite comprehensively
- Still contains explicit "disabled" / "No X" / "not available" framing.
- Needs positive local-first framing.

### Icons / branding
- **Status:** replace
- `10XbuilderLogo` appears in Login, Home hero, ContentView tab bar.
- Replace with 11x wordmark or system-styled "11x" text mark.

### Color / accent system
- **Status:** update tokens
- `Theme.swift` comment references "10x liquid glass theme".
- Accent `#33B93E` is bright/toy green. Target a calmer green in Pass 02.
- `billingStatusTint` helper should be renamed/deprecated.

### Spacing / layout density
- **Status:** keep
- Spacing tokens are reasonable. Main issue is card/badge visual weight, not spacing.

## Component Inventory

| Component | File location | Current state | Proposed change |
|-----------|---------------|---------------|-----------------|
| Home hero logo | `HomeView.swift` ~145 | `Image("10XbuilderLogo")` | Replace with 11x mark or styled text. |
| Tab bar home logo | `ContentView.swift` ~300 | `Image("10XbuilderLogo")` | Replace with 11x mark or SF Symbol. |
| Login animated logo | `LoginView.swift` ~101 | `Image("10XbuilderLogo")` | Replace with 11x mark. |
| Account tab | `AppTab.swift` ~20; `ContentView.swift` | `.account` kind, label "Account", icon `person.crop.circle` | Rename to `.settings`, label "Settings", icon `gearshape`. |
| Settings sidebar | `SettingsView.swift` | Sections: general, provider, usage | Rebuild: general, provider, storage, diagnostics, about. |
| Local cockpit card | `GeneralSettingsView.swift` | Shows "Billing: Disabled" / "Hosted deploy: Disabled" | Single positive summary; version rows. |
| Storage status card | `GeneralSettingsView.swift` | Database + Assets + Provider rows | Move to dedicated Storage section with copy/reveal buttons. |
| Provider status panel | `ProviderSettingsView.swift` | Shows endpoint/model/key | Keep; refine copy; remove billing note. |
| Provider endpoint editor | `ProviderSettingsView.swift` | Base URL, Model, SecureField | Keep; refine styling. |
| Local-mode notes | `ProviderSettingsView.swift` | 3-icon bullet list including billing | Reduce to one calm keychain/privacy note. |
| Usage/Diagnostics view | `UsageSettingsView.swift` | 4-row "No X" list | Single summary + optional diagnostics events. |
| Settings meta chip | `SettingsView.swift` shared | Status chip | Calmer styling, smaller. |
| Settings panel | `SettingsView.swift` shared | Card with stroke | Reduce visual weight. |
| Project card | `HomeView.swift` | iPhone mockup card | Add reveal/export actions later; keep structure. |
| Empty state card | `HomeView.swift` | Already local-cockpit framed | Make more action-oriented. |
| Suggestion chip | `HomeView.swift` | Random sample prompts | Remove billing example; add iOS-app-builder prompts. |
| Prompt composer | `HomeView.swift`, `ChatInputView.swift` | Dark rounded input | Normalize accent and focus ring. |
| Review centered state | `ReviewView.swift` | "No marketing assets yet" | Reframe as local review/export assets. |
| Review legal/section copy | `ReviewView.swift` | "App Store submission generation is not available" | Reframe as local export artifact editing. |
| Backend local banner | `BackendView.swift` | Good local-mode banner | Keep; remove remote-auth error below. |
| Environment setup UI | `EnvironmentVariablesView.swift` | Active Superwall/Supabase setup | Collapse/move to Diagnostics/Compatibility. |
| Onboarding step 0 | `OnboardingView.swift` | Local cockpit welcome | Keep; reframe billing bullet to positive. |
| Theme accent | `Theme.swift` | `#33B93E` | Calmer green token. |
| Theme comment | `Theme.swift` | "10x liquid glass theme" | Update to 11x. |
| `billingStatusTint` | `Theme.swift` | 10x-era helper | Rename/deprecate. |

## Risk Notes

1. **`AppTab.account` rename risk.** `AppTab` is `Codable` and persisted to `UserDefaults` via `ContentView.saveTabs()`. Renaming the `.account` kind will break decoding of previously saved tabs. Mitigation: keep the raw value string `"account"` but change the label/icon, or add a decode fallback. The safest change is to keep the enum raw value but rename the Swift enum case and update label/icon. If the raw value must change, implement a decode migration.

2. **`10XbuilderLogo` replacement.** This image asset may be referenced from multiple places. A simple replacement is to create an 11x-styled text mark (e.g., `Text("11x")` with a specific font/weight) to avoid adding new assets. Verify the asset is not used in SwiftUI previews or tests.

3. **Color change blast radius.** Changing `Theme.accent` affects every accent-colored element. Pass 02 must be limited to `Theme.swift` and shared components. A calmer green should still satisfy existing contrast tests.

4. **`EnvironmentVariablesView` scope.** The file is large (~3800 lines) and contains active hosted integration UI. Reframing it without deleting compatibility code is the main risk of Pass 06. Scope must remain copy/UI only; no model/service changes.

5. **`ReviewView` App Store framing.** The view is intentionally kept as a local artifact editor. The risk is over-correction: deleting the view or models would break local export. Scope is copy reframe only.

6. **Forbidden audit allowlist.** `EnvironmentVariablesView.swift` and `ReviewView.swift` are in the `scripts/forbidden-audit` legacy allowlist. New banned copy in those files will not fail the audit. Manual copy tests (Pass 09) are required.

7. **Existing tests will need updates.** `LocalCockpitUXTests`, `HostedVendorRemovalTests`, `ProductionGuideTests`, and potentially `AppStoreSubmissionTests` contain copy assertions that will break as UI copy changes. Coordinate test updates within each pass.

## Recommended Pass 02 Scope

UI Pass 02 should be limited to **design tokens and shared components** to minimize blast radius before larger view changes.

Smallest safe set of files:
- `10x-macos/Theme.swift` — update comment, accent color, add `accentSecondary`, rename/deprecate `billingStatusTint`.
- `10x-macos/Views/Settings/SettingsView.swift` — refine `SettingsMetaChip`, `SettingsPanel`, and shared settings containers.
- New reusable component: `LocalStatusBadge` or `LocalModeNote` in a new file under `10x-macos/Views/Common/` or `10x-macos/Views/Components/`.
- Optionally update `AppIdentity.localBadgeDetails` source in `10x-macos/Services/AppIdentity.swift` if the badge copy needs adjustment, but only if it does not affect persistence.

Explicitly **not** in Pass 02:
- No `ContentView` changes.
- No `HomeView` changes.
- No `SettingsSection` restructure.
- No provider/persistence logic changes.
- No new image assets unless absolutely required.

