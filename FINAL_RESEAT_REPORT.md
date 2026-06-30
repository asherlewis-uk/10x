# Final Reseat Report

## Summary

The 10x fork has been reseated as the local single-user 11x cockpit target.

Final product identity:

- App name: `11x`
- Bundle identifier: `app.kasey.11x`
- URL scheme: `elevenx`
- App support root: `~/Library/Application Support/11x`
- Preferences namespace: `app.kasey.11x`
- Keychain namespace: `app.kasey.11x`

Final build output inspected:

- App: `.derivedData/10x-macos/Build/Products/Debug/11x.app`
- Local zip sanity artifact: `.derivedData/10x-macos/Build/Products/Debug/11x-debug-local.zip`

Pass 11 included one minimal final fix: the Xcode project no longer declares, resolves, or links the stale `supabase-swift` package product, and its build-setting placeholders for `API_BASE_URL`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY` are empty. The rebuilt Xcode package graph resolves only `Sparkle`.

No vendor DMG was modified, unpacked, patched, resigned, overwritten, or depended on.

## Commit List

Reseat commits currently on `main` after `origin/main`:

- `b54bc0f` `docs(agents): define 11x local cockpit scope`
- `e19115d` `docs(audit): inventory 11x reseat surface`
- `edfe9b7` `reseat(local): isolate 11x app identity`
- `2c03a45` `reseat(entitlements): replace billing/credits/paywalls/Superwall with local unlimited single-user entitlement`
- `c8ef6a4` `chore(repo): ignore local agent cache`
- `76575c3` `reseat(db): replace Supabase runtime dependency with local SQLite persistence and single-user local profile`
- `e70af44` `reseat(storage): add local asset filesystem`
- `ea5709c` `reseat(provider): add openai-compatible adapter`
- `576812b` `reseat(hosted): remove or disable vendor-hosted deploy/publish paths`
- `9a9c0ef` `reseat(marketing): remove app-store submission and marketing flows, keep local export artifacts`
- `5890cb9` `reseat(local): pass 09 local cockpit UX reseat`
- `7d95c73` `test(local): pass 10 e2e test matrix and regression coverage`
- Pass 11 final report and Xcode cleanup: the commit containing this file.

## Files Changed By Area

Instruction and audit docs:

- `AGENTS.md`, `CLAUDE.md`, `README_11X_INIT_CONTEXT.md`
- `AUDIT_LOCALIZATION.md`, `PERSISTENCE_DECISION.md`, `FINAL_RESEAT_REPORT.md`
- `docs/10x-local-cockpit/*`
- `docs/archive/*`

Identity, build config, and app isolation:

- `AppInfo.plist`
- `10x-macos.xcodeproj/project.pbxproj`
- `10x-macos/10x_macos.entitlements`
- `10x-macos/Config.swift`
- `10x-macos/Configuration/Development.xcconfig`
- `10x-macos/Configuration/Production.xcconfig`
- `10x-macos/Services/AppIdentity.swift`
- `10x-macos/Services/TenXKeychainAccessGroup.swift`

Local entitlement and monetization removal:

- `10x-macos/Models/LocalEntitlements.swift`
- `10x-macos/Models/AppTab.swift`
- `10x-macos/ContentView.swift`
- `10x-macos/TenXAppApp.swift`
- `10x-macos/Views/Auth/LoginView.swift`
- `10x-macos/Views/Chat/*`
- `10x-macos/Views/HomeView.swift`
- `10x-macos/Views/Settings/*`
- Deleted `10x-macos/ViewModels/BillingViewModel.swift`
- Deleted `10x-macos/Views/Billing/BillingView.swift`

SQL persistence and local profile:

- `10x-macos/Services/DB/CockpitDatabase.swift`
- `10x-macos/Services/DB/MigrationSet.swift`
- `10x-macos/Services/DB/Repositories/*`
- `10x-macos/Services/DB/migrations/*.sql`
- `10x-macos/ViewModels/AuthManager.swift`
- `10x-macos/Services/SupabaseService.swift`
- `10x-macos/Services/SupabaseManagementService.swift`
- `10x-macos/Services/SupabaseManagementOAuthService.swift`

Local assets and export:

- `10x-macos/Services/LocalAssetStorage.swift`
- `10x-macos/Services/LocalProjectStore.swift`
- `10x-macos/Services/DB/Repositories/AssetRepository.swift`
- `10x-macos/ViewModels/BuilderViewModel+Preview.swift`
- `10x-macos/ViewModels/BuilderViewModel+Review.swift`

Provider adapter:

- `10x-macos/Services/Provider/OpenAIProviderAdapter.swift`
- `10x-macos/Services/Provider/ProviderConfig.swift`
- `10x-macos/Services/Provider/ProviderConfigRepository.swift`
- `10x-macos/Services/Provider/ProviderKeychainStore.swift`
- `10x-macos/Services/Builder/GenerationService.swift`
- `10x-macos/Services/Builder/BuilderContextManager.swift`
- `10x-macos/Models/ProjectIntegrations.swift`
- `10x-macos/Views/Settings/ProviderSettingsView.swift`

Hosted/App Store/marketing reseat:

- `10x-macos/Models/AppStoreSubmission.swift`
- `10x-macos/Models/AppStoreReview.swift`
- `10x-macos/Models/ProductionGuide.swift`
- `10x-macos/ViewModels/BuilderViewModel+AppStoreSubmission.swift`
- `10x-macos/ViewModels/BuilderViewModel+Review.swift`
- `10x-macos/Views/Preview/ReviewView.swift`
- `10x-macos/Views/Preview/ProductionView.swift`

Regression and audit coverage:

- `scripts/forbidden-audit`
- `10x-macosTests/*`
- `10x-macosTests/DB/*`
- `10x-macosTests/Provider/*`
- `10x-evalsTests/AppSessionStoreTests.swift`

## Features Removed

- Supabase SDK import/package dependency from SwiftPM runtime.
- Supabase package product from the Xcode app build graph.
- Supabase auth requirement for opening the cockpit.
- Supabase database persistence as the cockpit source of truth.
- Supabase management OAuth and remote management calls.
- Superwall runtime availability and advertised Superwall tools.
- Billing tab, pricing UI, credits UI, checkout, portal, invoices, promo, signup bonus, paywall, and purchase flows.
- Credit-based generation/export gates.
- Hosted vendor provider proxy for generation.
- Hosted app-store/legal page publish and unpublish actions.
- Vendor image/title/draft generation endpoints.
- Vendor updater feed and automatic Sparkle update checks.

## Features Replaced

- Supabase auth was replaced by a single local profile/session.
- Supabase data persistence was replaced by SQLite repositories.
- Supabase-hosted storage assumptions were replaced by local asset filesystem storage plus SQL metadata.
- Vendor provider proxy calls were replaced by an OpenAI-compatible BYOK/local-gateway adapter.
- Hosted publish/deploy flows were replaced by local folder and zip export paths.
- Billing/credits entitlement logic was replaced by local unlimited single-user entitlements.
- Account/billing settings were replaced by local status, storage, provider, and diagnostics settings.

## SQL Persistence

Decision: SQLite.

Database:

- Filename: `cockpit.sqlite`
- Default location: `~/Library/Application Support/11x/`
- Migrations: `10x-macos/Services/DB/migrations/`
- Migration table: `schema_migrations`

Repositories:

- `ProfileRepository`
- `ProjectRepository`
- `VersionRepository`
- `MessageRepository`
- `AppSettingsRepository`
- `UsageLogRepository`
- `AssetRepository`
- `ProviderConfigRepository`

Verification:

- Empty database migration is covered by `CockpitDatabaseTests`.
- Project CRUD, versions, messages, settings, usage diagnostics, and local profile persistence are covered by the SwiftPM test suite.
- Generation history persistence across database reloads is covered by `GenerationHistoryPersistenceTests`.

## Local Asset Storage

Local assets are written under `AppIdentity.appSupportDirectory/assets` by default.

Storage shape:

- Relative paths under `projects/<project_id>/...`
- Asset metadata in SQLite via `AssetRepository`
- Legacy local `tenx/` asset paths retained as read fallback for existing offline state

Verification:

- `LocalAssetStorageTests` covers path traversal rejection, relative path validation, writes, reads, and metadata behavior.
- `LocalExportIntegrationTests` covers folder export, zip creation, and provider-secret exclusion.

## Provider Adapter

Provider configuration keys:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL`
- `OPENAI_MODEL`

Provider storage:

- API key: OS Keychain via `ProviderKeychainStore`
- Public metadata: SQLite via `ProviderConfigRepository`
- Environment variables: development fallback only

Runtime behavior:

- Generation uses `OpenAIProviderAdapter`.
- Custom OpenAI-compatible base URLs are supported.
- Missing or invalid provider setup returns setup errors, not billing/credits/paywall errors.
- Provider metadata exposed to UI excludes raw secrets.

Verification:

- `OpenAIProviderAdapterTests`
- `ProviderConfigRepositoryTests`
- `GenerationServiceProviderTests`
- `LocalCockpitUXTests`

## Local Entitlements

The local entitlement source of truth is `LocalEntitlements`.

Final state:

- Mode: `single_user_unlimited`
- Generation: allowed
- Export: allowed
- Billing: disabled
- Credits: disabled
- Hosted vendor backend entitlement: disabled
- Usage tracking: local diagnostics only, never gating

Verification:

- `LocalEntitlementsTests`
- `NoSuperwallRuntimeTests`
- `LocalCockpitUXTests`
- `LocalExportIntegrationTests`

## UX Changes

User-facing 11x UX now emphasizes local operation:

- Local-mode badge: `11x`, `Single-user cockpit`, `Unlimited local`, `No billing`
- No login required for first project.
- Provider setup is visible in Settings.
- Database and asset storage status are visible in Settings.
- Usage settings show diagnostics only.
- Billing, credits, pricing, paywall, and checkout UI are unreachable.
- Review/App Store surfaces are local export/editing artifacts only.
- Backend/Integrations surfaces include local-mode warnings where legacy compatibility UI remains.

## Tests Added

- `10x-macosTests/AppIdentityIsolationTests.swift`
- `10x-macosTests/LocalEntitlementsTests.swift`
- `10x-macosTests/DB/CockpitDatabaseTests.swift`
- `10x-macosTests/DB/LocalAssetStorageTests.swift`
- `10x-macosTests/Provider/OpenAIProviderAdapterTests.swift`
- `10x-macosTests/Provider/OpenAIProviderURLProtocolStub.swift`
- `10x-macosTests/Provider/ProviderConfigRepositoryTests.swift`
- `10x-macosTests/Provider/GenerationServiceProviderTests.swift`
- `10x-macosTests/HostedVendorRemovalTests.swift`
- `10x-macosTests/LocalCockpitUXTests.swift`
- `10x-macosTests/NoSupabaseRuntimeTests.swift`
- `10x-macosTests/NoSuperwallRuntimeTests.swift`
- `10x-macosTests/GenerationHistoryPersistenceTests.swift`
- `10x-macosTests/LocalExportIntegrationTests.swift`
- `10x-macosTests/FirstLaunchIntegrationTests.swift`

## Commands Run And Results

Required Pass 11 commands:

- `git status --short`
  - Initial result before Pass 11 changes: clean.
  - After minimal Xcode cleanup before report: `M 10x-macos.xcodeproj/project.pbxproj`.
- `git diff --check`
  - Passed before changes.
  - Passed after the minimal Xcode cleanup.
- `xcrun swift test`
  - Passed after the minimal Xcode cleanup.
  - Result: 220 tests, 0 failures.
  - Non-blocking warnings: SwiftPM reports missing excluded files (`README.md`, `ROADMAP.md`, `ideas.md`, `.vercel`, `build`, `output`) and unhandled root docs.
- `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO`
  - Passed after the minimal Xcode cleanup.
  - Built `.derivedData/10x-macos/Build/Products/Debug/11x.app`.
  - Resolved Xcode packages after cleanup: `Sparkle` only.
  - Non-blocking warnings: existing Swift actor-isolation warnings and metadata extraction note.
- `./scripts/forbidden-audit`
  - Passed: no active runtime violations.
- `./scripts/forbidden-audit --inventory`
  - Passed active runtime checks.
  - Reported 3 legacy-inventory warning categories: monetization, Supabase, hosted deploy/updater.
- GitNexus `detect_changes`
  - MCP call: `detect_changes({ repo: "10x", scope: "all" })`
  - Result before report: 1 changed file, 0 changed symbols, 0 affected processes, low risk.

Additional Pass 11 packaging and identity checks:

- `plutil -p .derivedData/10x-macos/Build/Products/Debug/11x.app/Contents/Info.plist`
  - `CFBundleName`: `11x`
  - `CFBundleDisplayName`: `11x`
  - `CFBundleIdentifier`: `app.kasey.11x`
  - URL scheme: `elevenx`
  - `API_BASE_URL`: empty
  - `SUPABASE_URL`: empty
  - `SUPABASE_ANON_KEY`: empty
  - `SUFeedURL`: empty
  - `SUPublicEDKey`: empty
  - `SUEnableAutomaticChecks`: `false`
  - `SUAutomaticallyUpdate`: `false`
- `codesign -dv --verbose=4 .derivedData/10x-macos/Build/Products/Debug/11x.app`
  - Reported ad-hoc/linker signature due `CODE_SIGNING_ALLOWED=NO`.
- `codesign --verify -vvv --deep --strict .derivedData/10x-macos/Build/Products/Debug/11x.app`
  - Failed with `code has no resources but signature indicates they must be present`.
  - Classified as non-blocking for this unsigned debug build.
- `spctl -a -vvv -t execute .derivedData/10x-macos/Build/Products/Debug/11x.app`
  - Failed with the same unsigned/ad-hoc resource signature issue.
  - Classified as non-blocking for this unsigned debug build.
- `otool -L .derivedData/10x-macos/Build/Products/Debug/11x.app/Contents/MacOS/11x.debug.dylib`
  - Links Sparkle, system frameworks, CryptoKit, Security, SwiftUI, and SQLite.
  - No Supabase or Superwall dynamic library appears.
- `find .derivedData/10x-macos/Build/Products/Debug/11x.app -iname '*supabase*' -o -iname '*superwall*'`
  - No matches.
- `ditto -c -k --keepParent .derivedData/10x-macos/Build/Products/Debug/11x.app .derivedData/10x-macos/Build/Products/Debug/11x-debug-local.zip`
  - Passed.
  - Zip size: 12M.
- `unzip -l .derivedData/10x-macos/Build/Products/Debug/11x-debug-local.zip`
  - Passed and listed `11x.app` contents.

## Results

Final build and audit status:

- SwiftPM tests pass.
- Xcode app build passes with signing disabled.
- Built app identity is `11x` / `app.kasey.11x` / `elevenx`.
- Built app Info.plist has empty Supabase and vendor API placeholders.
- Xcode app build graph no longer resolves or links Supabase.
- Built app bundle has no Supabase/Superwall-named artifacts.
- Sparkle remains bundled, but updater feed/public key are empty and automatic checks/updates are disabled.
- Local unsigned zip packaging sanity passed.
- No hard blocker remains for the local debug build/reporting layer.

## Forbidden Audit Results

Default audit:

- `./scripts/forbidden-audit` passed.
- No active runtime violations were reported for forbidden Supabase/Superwall imports, active vendor endpoint defaults, billing/pricing/paywall settings routes, or credit gates.

Inventory audit:

- `./scripts/forbidden-audit --inventory` passed active runtime checks.
- It printed legacy references in 3 warning categories:
  - Legacy monetization code inventory.
  - Legacy Supabase code inventory.
  - Legacy hosted deploy/updater inventory.

Classification:

- Tests: legacy strings remain where tests prove absence, migration compatibility, generated-app guidance, or local-only artifact behavior.
- Archived docs: legacy 10x docs remain under `docs/archive/` as historical reference only.
- Inert/compatibility shims: `SupabaseService`, `SupabaseManagementService`, `SupabaseManagementOAuthService`, `SupabaseSchemaVisualizer`, `ProjectSuperwall`, `SuperwallManagementService`, and related model/tool input names remain as compatibility/dead-code candidates. Remote Supabase management OAuth always reports no usable session and throws local-cockpit unavailable errors.
- Generated-app/local artifact code: some Supabase/Superwall/App Store names remain in generated-app guidance, static analysis, export/review artifacts, and status rendering paths. These are tracked cleanup candidates and are not package/runtime dependencies.
- Updater code: Sparkle is still linked, but no vendor feed is active. Removing Sparkle entirely is a cleanup candidate, not a Pass 11 blocker.

The inventory mode is intentionally not strict. `--strict` would fail on retained legacy references and should be used only when the remaining shim/dead-code cleanup is in scope.

## Remaining Shims And Dead-Code Cleanup Candidates

- Delete or rename Supabase-named compatibility shims once UI/view-model call sites are fully localized:
  - `SupabaseService`
  - `SupabaseManagementService`
  - `SupabaseManagementOAuthService`
  - `SupabaseSchemaVisualizer`
  - `Supabase*` tool input and status model names
- Delete or rename Superwall dead-code surfaces:
  - `SuperwallManagementService`
  - `ProjectSuperwall`
  - `SuperwallToolHandlers`
  - inactive `superwall_manage` status/detail strings
- Remove remaining generated-app Supabase guidance if the product should no longer help users create Supabase-backed generated apps.
- Rename legacy diagnostic parameters such as `billingGroupId` and `billingMessagePreview` in provider/generation logs.
- Remove or rename `BillingModels.swift` if local diagnostics no longer need the retained display helper names.
- Remove Sparkle package/framework entirely if the final product does not want any updater framework bundled, even disabled.
- Rename repo structure/module names (`10x-macos`, `TenXApp`) if cosmetic cleanup becomes worthwhile. They are not final app identity.
- Clean SwiftPM exclude warnings for missing historical root files if desired.

## Remaining Hard Blockers Only

None for the Pass 11 local debug build, verification layer, and final reporting layer.

Unsigned/notarized distribution is not produced because Pass 11 verification explicitly used `CODE_SIGNING_ALLOWED=NO`; signing/notarization release packaging remains outside this local debug proof.

## Known Non-Goals

- Do not push.
- Do not modify, unpack, patch, resign, overwrite, or depend on the vendor DMG.
- Do not add new product features.
- Do not redesign UX.
- Do not reintroduce Supabase, Superwall, billing, credits, paywalls, checkout, hosted deploy, vendor auth, vendor backend, or vendor updater feeds.
- Do not create a signed/notarized public release package in this pass.
- Do not run hosted release scripts requiring signing, notarization, Sparkle feed publishing, Vercel, or vendor credentials.
- Do not remove every legacy-named compatibility shim unless a cleanup pass explicitly targets that.

## Final Acceptance Checklist

App isolation:

- [x] Vendor DMG remains untouched.
- [x] Local app display name is `11x`.
- [x] Local bundle identifier is `app.kasey.11x`.
- [x] Local app support path is `~/Library/Application Support/11x`.
- [x] Preferences namespace is `app.kasey.11x`.
- [x] Keychain namespace is `app.kasey.11x`.
- [x] Vendor updater feed is inactive.

Monetization removal:

- [x] No Superwall package/runtime dependency is active.
- [x] No pricing UI is reachable.
- [x] No credits UI is reachable.
- [x] No paywall UI is reachable.
- [x] No checkout flow is reachable.
- [x] No subscription flow is reachable.
- [x] No receipt validation or StoreKit purchase flow is part of 11x monetization.
- [x] Usage tracking is local diagnostics only and never gates generation/export.

Local entitlements:

- [x] Single local entitlement source of truth exists.
- [x] Generation is allowed.
- [x] Export is allowed.
- [x] Billing is disabled.
- [x] Credits are disabled.
- [x] Hosted vendor backend entitlement is disabled.

Supabase removal:

- [x] No Supabase SDK import remains.
- [x] No Supabase SwiftPM package dependency remains.
- [x] No Supabase Xcode package product dependency remains.
- [x] No Supabase URL/key is required for launch.
- [x] Supabase auth is replaced by local profile/session.
- [x] SQL migrations are the cockpit source of truth.
- [x] Remaining Supabase names are classified above as compatibility/dead-code/generated-app cleanup candidates.

SQL persistence:

- [x] Empty DB migrates cleanly.
- [x] Project CRUD works.
- [x] Generation history persists.
- [x] Settings persist.
- [x] Local profile persists.
- [x] Migration table/versioning exists.
- [x] Test DB initialization works.

Local assets:

- [x] Assets write to local filesystem.
- [x] Asset metadata persists in SQL.
- [x] Path traversal is rejected.
- [x] Local export is covered by integration tests.
- [x] Existing assets can be read from local storage paths.

Provider adapter:

- [x] OpenAI-compatible adapter exists.
- [x] Custom base URL is supported.
- [x] Local gateway shape is supported.
- [x] Provider key is stored through Keychain.
- [x] Missing key shows setup error.
- [x] Invalid provider setup shows setup error.
- [x] No vendor provider endpoint is hardcoded for generation.

Hosted/App Store/marketing:

- [x] Vendor hosted deploy is disabled/removed from active local-cockpit paths.
- [x] Local export replaces hosted publish.
- [x] App Store submission artifacts are local-only.
- [x] Marketing flows are removed or local-export only.
- [x] No vendor hosted URL is required.

UX:

- [x] Local mode badge is visible.
- [x] No login is required for first project.
- [x] Provider setup is visible.
- [x] Database status is visible.
- [x] Asset path/status is visible.
- [x] Billing/credits/paywall copy is not present in active local setup surfaces.

Tests/build/audit:

- [x] Static forbidden import/runtime audit exists.
- [x] Local entitlement tests exist.
- [x] SQL migration/repository tests exist.
- [x] Asset storage tests exist.
- [x] Provider adapter tests exist.
- [x] First-launch integration test exists.
- [x] Local export integration test exists.
- [x] Reload/generation persistence integration test exists.
- [x] `xcrun swift test` passes.
- [x] Xcode app build passes with `CODE_SIGNING_ALLOWED=NO`.
- [x] Final forbidden audit passes.
- [x] GitNexus `detect_changes` was run before commit.
- [x] `FINAL_RESEAT_REPORT.md` is complete.

Not applicable to this Swift/Xcode repo:

- npm/pnpm install, typecheck, lint, and build commands were not run. The equivalent Swift/Xcode verification surfaces above were run instead.
