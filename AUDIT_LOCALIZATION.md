# Audit Localization

## Pass Scope And Evidence

Pass: Pass 01, inventory and audit only.

Runtime behavior changed: none.

Files created in this pass:

- `AUDIT_LOCALIZATION.md`

Files archived or moved in this pass:

- None.

Archived files treatment:

- `docs/archive/` is historical reference only and was not treated as current scope.

Current authoritative docs:

- `AGENTS.md`
- `README_11X_INIT_CONTEXT.md`
- `docs/10x-local-cockpit/00_MASTER_E2E_RESEAT_PLAN.md`
- `docs/10x-local-cockpit/01_AGENT_EXECUTION_PROMPT.md`
- `docs/10x-local-cockpit/02_PASS_01_INVENTORY_AND_AUDIT.md`
- `docs/10x-local-cockpit/16_LOCAL_IMPLEMENTATION_DEFAULTS.md`

Primary source files read or inspected:

- `10x-macos/AppInfo.plist`
- `10x-macos.xcodeproj/project.pbxproj`
- `Package.swift`
- `10x-macos/10x_macos.entitlements`
- `10x-macos/10x_macos_Release.entitlements`
- `10x-macos/Configurations/Development.xcconfig`
- `10x-macos/Configurations/Production.xcconfig`
- `10x-macos/Config.swift`
- `10x-macos/APIClient.swift`
- `10x-macos/TenXAppApp.swift`
- `10x-macos/SparkleUpdater.swift`
- `10x-macos/Services/AppUpdateChannel.swift`
- `10x-macos/ViewModels/AuthManager.swift`
- `10x-macos/Services/SupabaseService.swift`
- `10x-macos/Services/SupabaseManagementOAuthService.swift`
- `10x-macos/Services/SupabaseManagementService.swift`
- `10x-macos/Services/SupabaseSchemaVisualizer.swift`
- `10x-macos/Services/SuperwallManagementService.swift`
- `10x-macos/Services/AuthKeychainStore.swift`
- `10x-macos/Services/ProjectKeychainStore.swift`
- `10x-macos/Services/LocalProjectStore.swift`
- `10x-macos/Services/APIClient.swift`
- `10x-macos/ViewModels/BillingViewModel.swift`
- `10x-macos/Models/BillingModels.swift`
- `10x-macos/Models/AppTab.swift`
- `10x-macos/Models/AppStoreSubmission.swift`
- `10x-macos/Models/ProjectEnvironmentSecurity.swift`
- `10x-macos/Models/ProjectIntegrations.swift`
- `10x-macos/Models/ProjectSuperwall.swift`
- `10x-macos/Models/ProjectBackend.swift`
- `10x-macos/Models/ProductionGuide.swift`
- `10x-macos/Services/AppStoreSubmissionFactCollector.swift`
- `10x-macos/Services/Builder/ToolExecutor.swift`
- `10x-macos/Services/Builder/BuilderToolDefinitions.swift`
- `10x-macos/Services/Builder/BuilderPrompts.swift`
- `10x-macos/Services/Builder/BundledSkillsCatalog.swift`
- `10x-macos/Services/Builder/SkillsManager.swift`
- `10x-macos/ViewModels/BuilderViewModel+Generation.swift`
- `10x-macos/ViewModels/BuilderViewModel+AppStoreSubmission.swift`
- `10x-macos/ViewModels/BuilderViewModel+Review.swift`
- `10x-macos/ContentView.swift`
- `10x-macos/Views/Billing/BillingView.swift`
- `10x-macos/Views/Settings/UsageSettingsView.swift`
- `10x-macos/Views/Preview/EnvironmentVariablesView.swift`
- `10x-macos/Views/Preview/BackendView.swift`
- `10x-macos/Views/Preview/ProductionView.swift`
- `10x-macos/Views/Preview/ReviewView.swift`
- `10x-evals/AppSessionStore.swift`
- `10x-evals/EvalRunner.swift`
- `scripts/evals`
- `scripts/release/*`

Searches run:

- Monetization: `Superwall|superwall|pricing|price|credits?|billing|subscription|paywall|purchase|receipt|StoreKit|RevenueCat|Stripe|checkout`
- Supabase: `Supabase|supabase|@supabase|SUPABASE|anonKey|service_role|service-role|createClient`
- Hosted and marketing: `hosted|deploy|publish|submit|submission|App Store|app-store|marketing|analytics|telemetry`
- Config, provider, updater: `apiBaseURL|baseURL|OpenAI|OPENAI|updater|Sparkle|downloads|feedURL|SUFeedURL|SUPublicEDKey|SPUUpdater`
- Targeted follow-ups for Supabase Edge Functions, storage buckets, analytics/tracking, release scripts, and build/test entry points.

Scope decisions captured:

- Pass 01 is inventory-only.
- Do not implement Pass 02 app identity changes yet.
- Do not delete Supabase, Superwall, billing, Sparkle, hosted deploy, app-store, or marketing code yet.
- Do not use docs as proof for current runtime behavior; source and scripts were inventoried directly.
- Treat archived docs as historical only.

Conflicts avoided:

- No runtime source was modified.
- No release scripts were executed.
- No build or test command was run as part of this audit.
- No vendor DMG was modified, unpacked, patched, resigned, overwritten, or depended on.
- No push was performed.

## Summary

The active source is still a 10x-era hosted product shell. It contains active runtime paths for 10x identity, Supabase auth/database/management, Superwall management, billing and credits, hosted app-store/legal page publishing, Sparkle updater feeds, vendor-style API calls, and hosted release scripts.

The target state is the locked 11x local cockpit:

- App name: `11x`
- Bundle ID: `app.kasey.11x`
- URL scheme: `elevenx`
- Persistence: SQLite in app support by default
- Asset storage: app support filesystem
- Provider configuration: OpenAI-compatible BYOK/local gateway using `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL`
- Usage tracking: local diagnostics only, never gating

Least-risk database option after inventory: SQLite.

Reason: the cockpit persistence currently flows through Supabase tables and local JSON/files, but no active cockpit persistence layer was found that requires Postgres-only SQL semantics. Supabase Management and Edge Function support expose Postgres-like generated-app operations, but those are vendor hosted/backend features to delete or replace, not a reason for the local cockpit to require Postgres.

## App Identity

Current active identity:

- `10x-macos/AppInfo.plist` sets `CFBundleName` and `CFBundleDisplayName` to `10x`.
- `10x-macos.xcodeproj/project.pbxproj` uses product name `10x`, target name `10x-macos`, and product `10x.app`.
- Debug and Release build settings use `PRODUCT_BUNDLE_IDENTIFIER = app.10x.macos`.
- `10x-macos/TenXAppApp.swift` opens a window titled `10x`.
- `Package.swift` package name is `TenXApp`; executable products include `TenXApp` and `10x-evals`.
- `10x-evals/AppSessionStore.swift` uses default suite `app.10x.macos`.
- Keychain services use `app.10x.macos.auth`, `app.10x.macos.auth.tokens`, and derived services such as `app.10x.macos.auth.billing`.
- Project environment Keychain service prefix is `com.tenx.project-environment`.
- Local project storage root is `~/Library/Developer/TenXApp`.

Classification:

- Replace: display name, bundle ID, product name, app window title, URL scheme, preferences namespaces, app support root, Keychain namespaces, eval suite names.
- Keep temporarily: source module names until Pass 02 decides the lowest-risk rename sequence.
- Delete or replace: vendor updater/feed identity and hosted release identity.

Target:

- App name: `11x`
- Bundle ID: `app.kasey.11x`
- URL scheme: `elevenx`
- App support directory: `11x`
- Preferences, Keychain, cache, and log namespaces should be `app.kasey.11x` scoped.

## Bundle Identifiers

Current active identifiers:

- App bundle ID: `app.10x.macos`.
- URL type name: `app.10x.macos`.
- Entitlement keychain access group: `$(AppIdentifierPrefix)app.10x.shared`.
- Auth Keychain service: `app.10x.macos.auth`.
- Auth token service: `app.10x.macos.auth.tokens`.
- Billing claim service derives from auth service as `.billing`.
- Supabase management token storage derives from `app.10x.macos.auth.integrations.supabase-management`.

Classification:

- Replace: all runtime, build, entitlements, Keychain, URL, and preference identifiers.
- Do not reuse: app groups, Keychain services, or preference domains from the 10x-era app.

## URL Schemes

Current active URL scheme:

- `10x-macos/AppInfo.plist` registers `app.10x.macos`.
- `AuthManager` uses `app.10x.macos://auth/callback` for auth callbacks.
- `BillingViewModel` and `ContentView` handle billing deep links on the `app.10x.macos` scheme with host `billing`.

Classification:

- Replace auth/deep-link scheme with `elevenx` only if a local deep-link feature remains.
- Delete billing deep-link handling when billing is removed.
- Do not use `asherlewis.online://`; the domain is only for optional future Universal Links.

## Vendor Backend / Hosted URLs

Current active hosted/vendor URLs:

- `Config.apiBaseURL` reads `API_BASE_URL` and defaults to `http://localhost:8000`.
- Release build settings set `API_BASE_URL = https://api.example.invalid/`.
- `APIClient` groups requests under `builder`, `builder/skills`, `billing`, and `admin`.
- `APIClient` sends 10x-specific headers: `X-10x-Api-Version`, `X-10x-Credit-Units`, `X-10x-App-Version`, `X-10x-App-Build`, and `X-10x-Platform`.
- `Config.hostedAppsBaseURL` defaults to `https://apps.example.invalid`.
- App-store submission publishing uses `Config.hostedAppsBaseURL` for hosted legal and support pages.
- Supabase Management OAuth starts through vendor backend endpoints under `builder/supabase/oauth/*`.
- App-store icon/review generation uses vendor backend endpoints such as `builder/openai/images/generate`.
- Generation and app-store submission draft generation use backend stream paths such as `builder/claude/stream`.

Classification:

- Delete: vendor production backend dependency.
- Replace: generation/provider calls with a local OpenAI-compatible adapter.
- Replace: hosted app-store/legal page publishing with local folder and zip export.
- Delete: billing/admin vendor endpoints.
- Stub local-only only where needed to keep UI responsive during intermediate passes.

## Supabase Usage

### Auth

Active auth surfaces:

- `AuthManager` imports Supabase and states it manages authentication via Supabase.
- OAuth starts at `Config.supabaseURL/auth/v1/authorize`.
- OAuth callback uses scheme `app.10x.macos://auth/callback`.
- Refresh flow calls `Config.supabaseURL/auth/v1/token?grant_type=refresh_token`.
- User fetch calls `Config.supabaseURL/auth/v1/user`.
- Native Apple sign-in calls `SupabaseService.shared.signInWithApple`.
- Auth state sync uses Supabase SDK session APIs and auth state change streams.
- `AuthKeychainStore` imports Supabase auth local storage types and stores 10x auth tokens.
- `10x-evals/AppSessionStore.swift` reads `tenx_*` tokens and Supabase auth storage keys.
- `10x-evals/EvalRunner.swift` refreshes sessions through Supabase auth endpoints.

Classification:

- Delete: vendor/Supabase auth runtime.
- Replace: with local single-user profile/session state.
- Keep only as migration/audit notes until removal.

### Database

Active database surfaces:

- `SupabaseService` constructs `SupabaseClient` using `Config.supabaseURL` and `Config.supabaseAnonKey`.
- `SupabaseService` performs CRUD on `builder_projects`, `builder_versions`, `builder_conversations`, `builder_messages`, and `published_app_store_pages`.
- `BuilderViewModel+AppStoreSubmission` writes app-store submission settings and published pages through Supabase.
- `LocalProjectStore` already stores substantial project state locally as JSON and files, but it still syncs environment metadata and aliases Supabase client variables.
- `SupabaseManagementService` exposes project/org/schema/table/query/auth/settings operations against the Supabase Management API.

Classification:

- Replace cockpit persistence with a repository-backed SQL layer.
- Delete Supabase SDK dependency from runtime.
- Delete Supabase Management API paths or convert only the non-hosted concepts to local equivalents.
- SQLite is the least-risk local default.

Expected SQLite mapping candidates:

- `local_profile`
- `projects`
- `project_files`
- `generations`
- `generation_steps`
- `assets`
- `provider_configs`
- `provider_key_metadata`
- `usage_logs`
- `app_settings`
- `export_jobs`
- `diagnostic_events`
- `schema_migrations`

### Storage

Active storage surfaces:

- No direct Supabase object storage upload/download runtime path was found for cockpit assets.
- `SupabaseManagementService` and builder tool definitions can inspect or mutate Supabase storage metadata such as `storage.buckets`.
- `BundledSkillsCatalog` and `BuilderToolDefinitions` include Supabase storage bucket guidance for generated projects.
- `LocalProjectStore` already stores local project artifacts under `~/Library/Developer/TenXApp`, including chat data, status, preview screens, captured screens, app-store review assets, environment metadata, `.env.local`, and attachments/images.
- `ProjectKeychainStore` stores hosted secret values locally in Keychain.

Classification:

- Keep and reseat: local filesystem asset storage concept.
- Replace location: move from `~/Library/Developer/TenXApp` to the 11x app support directory.
- Delete: Supabase storage bucket management as a first-class cockpit dependency.
- Keep only if later converted into generated-app guidance that does not make 11x depend on Supabase.

### Realtime

Active realtime surfaces:

- No active Supabase Realtime channel subscription path was found in cockpit runtime.
- Supabase schema inspection excludes a `realtime` schema.
- Supabase auth state changes are active but should be counted under auth, not app data realtime.

Classification:

- Delete Supabase realtime references where present.
- Replace with local state invalidation/events only if a realtime-like app event bus is needed.

### Edge Functions

Active Edge Function surfaces:

- Builder backend tools scaffold `supabase/functions/<name>/index.ts`.
- Backend deployment calls Supabase Management API `/v1/projects/{projectRef}/functions/deploy`.
- Backend tools include `status`, `link_provider`, `upsert_function`, `deploy`, `invoke`, `set_secret`, and `list_logs`.
- `SupabaseManagementOAuthService` requests `edge_functions_write` and `edge_functions_secrets_write`.
- `ProjectBackend` and backend views track Supabase function status, deploy state, logs, and failures.
- Tests assert deploy approvals and Supabase Edge Function paths.

Classification:

- Delete hosted Supabase Edge Function deploy as an active 11x cockpit feature.
- Replace any required export behavior with local folder and zip export.
- Keep generated project files only as local artifacts if export flows need to preserve user project contents.

### Generated Types

Active generated type surfaces:

- No dedicated checked-in Supabase generated database types file was found.
- Active app models are Swift Codable domain models decoded from Supabase responses.
- Supabase schema visualizer and management services infer schema at runtime from Supabase APIs.

Classification:

- No generated Supabase type file needs migration.
- Replace Codable persistence boundaries with SQLite repositories and explicit migrations.

### Environment Variables

Active Supabase environment variables:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_PUBLISHABLE_KEY`
- Supabase management token/key fields in Keychain-backed integration flows.

Active config files:

- `AppInfo.plist`
- `Development.xcconfig`
- `Production.xcconfig`
- `Config.swift`
- `ProjectIntegrations.swift`
- `ProjectEnvironmentSecurity.swift`
- `LocalProjectStore.swift`
- `EnvironmentVariablesView.swift`

Classification:

- Delete as runtime requirements.
- Remove default placeholders from app build config during Supabase removal.
- Preserve only in migration notes or generated-project export artifacts if explicitly needed later.

## Superwall Usage

Active Superwall surfaces:

- `SuperwallManagementService` talks to `https://api.superwall.com`.
- `ProjectSuperwall` tracks linked organization, project, application, paywall, product, campaign, entitlement, and test user state.
- Builder tool definitions support Superwall actions such as dashboard linking, paywall listing, paywall opening, starter monetization, products, campaigns, entitlements, and test users.
- Builder prompts and bundled skills route paywall/subscription work to Superwall.
- `ProjectIntegrations` exposes `SUPERWALL_PUBLIC_API_KEY`.
- Assets include `SuperwallLogo` and `SuperwallWordmark`.
- Tests assert Superwall management behavior and prompt routing.

Classification:

- Delete entirely from 11x runtime.
- Delete or archive Superwall assets and integration state in later passes.
- Remove prompt routing that asks agents to use Superwall.
- Remove tests that assert Superwall behavior or rewrite them to assert absence.

## Monetization

### Superwall

Classification:

- Delete.

See `Superwall Usage`.

### Credits

Active credit surfaces:

- `BillingModels` models credit balances, credit packs, credit grants, credit events, usage charges, daily limits, and credit metadata.
- `BillingViewModel` computes total credits, daily remaining credits, and credit-related state.
- `UsageSettingsView` displays credit totals, daily limits, usage charges, and latest message costs.
- `APIClient` sends `X-10x-Credit-Units`.
- `Config.creditUnits` is set to `normalized`.
- `BuilderViewModel` tracks billing group IDs and billing message previews for generation.

Classification:

- Delete credit gating and purchase accounting.
- Replace usage records only with local diagnostics, never gates.
- Remove credit headers from provider/runtime requests.

### Pricing UI

Active pricing surfaces:

- `BillingView` shows plans, packs, credits, subscription state, payment method, invoices, and checkout actions.
- `BillingViewModel` loads catalog, plans, packs, and invoices.
- `AppTab` and `ContentView` make billing/account UI reachable.
- Release notes include billing/pricing messaging.

Classification:

- Delete pricing UI from reachable runtime.
- Replace account/settings surfaces with local provider, storage, and diagnostics settings.

### Billing / Subscription

Active billing/subscription surfaces:

- `BillingViewModel` hits `billing/bootstrap`, `billing/invoices`, `billing/portal`, checkout, promo, and phone OTP endpoints.
- `BillingModels` includes subscriptions, plans, invoices, payment methods, daily limits, usage pricing plans, and hosted invoice URLs.
- `DeviceFingerprintService` tracks signup bonus claims using Keychain.
- `ContentView` refreshes billing after authentication and opens billing tabs/deep links.
- `AppInfo.plist`, xcconfigs, and `Config.swift` contain `BILLING_TEST_MODE`, `PAYMENTS_ENABLED`, and `SIGNUP_BONUS_ENABLED`.

Classification:

- Delete subscription and billing runtime.
- Delete signup bonus and promo flows.
- Replace usage display with local diagnostics only if useful.

### StoreKit / Receipt Validation

Active StoreKit/receipt surfaces:

- No first-party StoreKit purchase controller or receipt validator was found in the cockpit runtime.
- `AppStoreSubmissionFactCollector` detects StoreKit/subscription usage in generated projects.
- Tests include generated-project StoreKit detection fixtures.

Classification:

- Delete or keep as generated-project static analysis only if local export workflows still need App Store metadata.
- Do not introduce StoreKit purchase flow.

### Stripe / Checkout

Active Stripe/checkout surfaces:

- `BillingViewModel` calls backend checkout endpoints for subscriptions and packs.
- Billing invoice models include `hosted_invoice_url`.
- Builder prompts mention Stripe webhooks for generated apps.
- Onboarding examples include Stripe as a sample app.
- No direct Stripe SDK import was found in the cockpit runtime.

Classification:

- Delete checkout flow and hosted invoice handling.
- Remove Stripe from first-party 11x monetization context.
- Generated-app examples can remain only if clearly unrelated to 11x billing after later cleanup.

## Hosted Capabilities

### Hosted Deploy

Active hosted deploy surfaces:

- Supabase Edge Function deploy paths are active in builder backend tooling.
- Release scripts publish app downloads and update feeds through hosted site artifacts.
- `scripts/release/deploy-vercel.sh` deploys the release site using Vercel.
- `Config.hostedAppsBaseURL` backs hosted app-store/legal page URLs.
- Builder prompts currently say 10x does not provide generic deployment infrastructure, while other paths still deploy Supabase backend functions.

Classification:

- Delete vendor hosted deploy as a cockpit dependency.
- Replace user output with local folder export and zip export.
- Keep local project file generation.
- Do not run release/hosted deploy scripts by default during reseat.

### Publishing

Active publishing surfaces:

- App-store submission pages can be published/unpublished through Supabase.
- Published pages use `published_app_store_pages`.
- `AppStoreSubmission.hostedURL` generates hosted legal/support URLs.
- Release scripts publish appcast, latest metadata, release notes, and site assets.

Classification:

- Replace hosted publishing with local export artifacts.
- Delete Supabase-hosted page persistence.
- Keep export packet logic if converted to local-only output.

### App Store / Submission

Active app-store submission surfaces:

- `AppStoreSubmission` models facts, declarations, review notes, hosted URLs, publish state, and blockers.
- `ReviewView` exposes App Store review/submission UI and tracking declarations.
- `AppStoreSubmissionFactCollector` scans generated projects for permissions, billing, auth, analytics, tracking, StoreKit, and integrated services.
- `BuilderViewModel+AppStoreSubmission` can generate drafts through the vendor backend and publish pages through Supabase.
- Tests assert app-store submission behavior.

Classification:

- Delete hosted/vendor app-store submission flow unless converted to local export-only artifacts.
- Keep local export packet generation only if it remains useful and does not publish or require hosted/vendor services.
- Remove publish/unpublish state and hosted URL assumptions.

### Marketing Assets / Flows

Active marketing surfaces:

- App-store/legal/support hosted page templates and release site templates exist under `scripts/release`.
- App-store submission models include marketing URL and support URL fields.
- Generated project review and production guides include marketing/release readiness language.
- Release notes include SaaS/billing marketing copy.
- Home/onboarding examples include third-party SaaS examples.

Classification:

- Delete marketing tied to SaaS monetization and hosted publishing.
- Keep only local export-oriented copy if needed.
- Treat release notes and release templates as historical/release-script inventory until Pass 11.

## Provider Integrations

### OpenAI

Active OpenAI surfaces:

- `ProjectIntegrations` exposes `OPENAI_API_KEY`, but currently scopes it as hosted/backend and says it syncs to Supabase secrets.
- `ProjectEnvironmentSecurity` knows `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL`.
- `BuilderViewModel+Review` calls vendor backend `openai/images/generate`.
- Generation/app-store draft flows call backend `claude/stream` paths and pass model names through vendor APIs.
- OpenAI logo assets exist.

Missing for target:

- No direct local OpenAI-compatible provider adapter was found.
- `OPENAI_BASE_URL` and `OPENAI_MODEL` are recognized by security metadata but are not the primary app generation path.

Classification:

- Replace vendor provider proxy with local OpenAI-compatible adapter.
- Keep `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL` as target provider keys.
- Store provider secrets in Keychain first, encrypted local config second, and env only as a development fallback.

### Other Providers

Active other-provider surfaces:

- Claude/Anthropic is implied by backend generation endpoints and model names.
- Supabase and Superwall are treated as integrations, not model providers.

Classification:

- Replace vendor-specific model/backend paths with OpenAI-compatible provider abstraction.
- Keep support for local gateways/OpenRouter/Ollama/vLLM only if exposed through OpenAI-compatible semantics.

### Secret Handling

Active secret handling surfaces:

- `AuthKeychainStore` stores Supabase/auth tokens.
- `ProjectKeychainStore` stores hosted project environment secret values locally.
- `ProjectEnvironmentSecurity` classifies public/client/hosted variables and sensitive keys.
- `LocalProjectStore` writes client variables to `.env.local` and metadata to `environment.json`.
- Supabase management OAuth tokens are stored for hosted management operations.

Classification:

- Keep Keychain as the preferred secret primitive.
- Replace service namespaces with `app.kasey.11x`.
- Delete Supabase/Superwall/billing token storage.
- Reseat provider keys into local provider config storage.

## Updater

Active updater surfaces:

- `Package.swift` depends on Sparkle.
- The Xcode project references Sparkle.
- `AppInfo.plist` enables automatic checks and automatic updates and sets `SUFeedURL`, `SUPublicEDKey`, and `DEFAULT_UPDATE_CHANNEL`.
- `SparkleUpdaterCoordinator` starts Sparkle, checks update information at launch, presents update prompts, and supports manual `Check for Updates`.
- `AppUpdateChannel` supports stable/beta channels and maps beta to Sparkle allowed channels.
- `TenXAppApp` activates the updater on launch and adds a Check for Updates command.
- Release scripts generate appcast files and site metadata for Sparkle feeds.

Classification:

- Disable or remove updater unless replaced with an owned 11x local release channel.
- Do not reuse vendor feed, key, channel, release site, or appcast assumptions.
- Pass 02 should isolate identity before any update behavior can be considered safe.

## Analytics / Telemetry

Active analytics/telemetry surfaces:

- No first-party external analytics SDK dependency was found for the cockpit runtime.
- App-store submission fact collection detects analytics/tracking in generated apps.
- Review UI exposes tracking declarations for App Store metadata.
- Production guide text tells generated apps to confirm analytics/logs/crash reporting.
- Billing credit events and usage charges are active but are monetization telemetry, not local diagnostics.
- Superwall campaign event names exist for paywall targeting.

Classification:

- Delete billing/Superwall telemetry and any conversion-related paths.
- Keep only local diagnostics needed for troubleshooting.
- Generated-app analytics detection may remain only if app-store local export artifacts survive later passes.

## Storage

Current storage inventory:

- Local filesystem project storage already exists in `LocalProjectStore`.
- Storage root is 10x-branded: `~/Library/Developer/TenXApp`.
- Stored artifacts include project JSON, chat transcripts, environment metadata, `.env.local`, preview images, captured images, review images, and attachments.
- Hosted secret values are stored through Keychain, not plaintext project JSON.
- Supabase storage appears as schema/bucket management guidance rather than active object storage for the cockpit.

Classification:

- Keep local filesystem storage pattern.
- Replace path and metadata with 11x app support defaults.
- Add SQLite asset metadata when persistence pass begins.
- Delete hosted/Supabase storage assumptions.

## Persistence

Current persistence inventory:

- Supabase tables hold server-side project/chat/version/published page state.
- Local JSON/files hold a substantial project cache and workspace state.
- UserDefaults persists tabs, update channel preference, and other app-local UI state.
- Keychain stores auth tokens, Supabase management tokens, hosted env secrets, and billing claim markers.
- No checked-in SQL migration layer was found for cockpit persistence.

Classification:

- Replace Supabase persistence with SQLite repositories.
- Keep local file artifacts for large assets and generated project contents.
- Keep UserDefaults only for non-sensitive UI preferences after namespace isolation.
- Keep Keychain only for 11x-local provider secrets and sensitive config.

Least-risk database decision:

- Use SQLite.
- Postgres is not justified by the current cockpit source because Postgres-like operations are tied to Supabase Management/generated-app backend tooling rather than local cockpit persistence.

## Tests And Build Commands

Inventory commands from authoritative docs and scripts:

- macOS app build:
  `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO`
- SwiftPM tests:
  `swift test`
- Eval runner build:
  `./scripts/evals build`
- Smoke eval suite:
  `./scripts/evals smoke`

`scripts/evals` behavior:

- Uses Xcode project `10x-macos.xcodeproj`.
- Defaults suite to `evals/smoke-suite.yml`.
- If a shared `10x-evals` scheme exists, builds with `xcodebuild`.
- Otherwise builds with `swift build --package-path "$ROOT" --product 10x-evals`.
- Supports `list`, `build`, `smoke`, and `run`.

Known test surfaces:

- `10x-macosTests/AppStoreSubmissionTests.swift`
- `10x-macosTests/AppUpdateChannelTests.swift`
- `10x-macosTests/AppleSignInConfigurationTests.swift`
- `10x-macosTests/AuthKeychainStoreTests.swift`
- `10x-macosTests/BuilderGenerationRequestPlannerTests.swift`
- `10x-macosTests/BuilderIntegrationToolTests.swift`
- `10x-macosTests/BuilderProjectStatusStateTests.swift`
- `10x-macosTests/BuilderViewModelGenerationInvokeTests.swift`
- `10x-macosTests/BuilderViewModelRevertTests.swift`
- `10x-macosTests/ExistingProjectImporterTests.swift`
- `10x-macosTests/LocalProjectStoreEnvironmentTests.swift`
- `10x-macosTests/ProductionGuideTests.swift`
- `10x-macosTests/ProjectBackendStateTests.swift`
- `10x-macosTests/ProjectIntegrationSupportTests.swift`
- `10x-macosTests/SupabaseManagementServiceTests.swift`
- `10x-macosTests/SupabaseSchemaVisualizerTests.swift`
- `10x-macosTests/SuperwallManagementServiceTests.swift`
- `10x-macosTests/ToolExecutorTests.swift`
- `10x-macosTests/XcodePreviewServiceTests.swift`
- `10x-evalsTests/AppSessionStoreTests.swift`
- `10x-evalsTests/EvalQuestionResponderTests.swift`
- `10x-evalsTests/EvalSuiteTests.swift`

Classification:

- Keep build/test commands as proof surfaces, but expect many tests to require rewrites as Supabase, Superwall, billing, updater, and hosted flows are removed.
- Add new tests in later passes proving the app boots without Supabase, Superwall, credits, billing, hosted services, and vendor backend config.

## Release Scripts

Release script inventory:

- `scripts/release/ExportOptions.plist.template`
- `scripts/release/build-release.sh`
- `scripts/release/create-dmg.sh`
- `scripts/release/deploy-vercel.sh`
- `scripts/release/diagnose-updater.sh`
- `scripts/release/export-sparkle-private-key.sh`
- `scripts/release/import-developer-id-cert.sh`
- `scripts/release/notarize-dmg.sh`
- `scripts/release/publish-beta.sh`
- `scripts/release/publish-release.sh`
- `scripts/release/release-common.sh`
- `scripts/release/render-dmg-app-icon.swift`
- `scripts/release/render-dmg-background.swift`
- `scripts/release/store-notary-credentials.sh`
- `scripts/release/verify-release.sh`
- `scripts/release/templates/appcast.xml`
- `scripts/release/templates/index.html`
- `scripts/release/release-notes/*.html`

Active release assumptions:

- App name, slug, bundle name, and scheme are 10x-era.
- Release packaging assumes signing/notarization.
- Sparkle appcasts and update feeds are produced.
- Hosted download site publishing is supported.
- Vercel deployment requires Vercel credentials.

Classification:

- Do not treat release scripts as default local proof commands during early reseat.
- Replace or disable hosted/Sparkle/Vercel release publishing in later passes.
- Keep packaging scripts only if reseated to local 11x packaging without vendor update feeds.

## Test Coverage Found

Coverage exists for:

- App update channel logic.
- Auth Keychain storage and Supabase auth storage migration.
- Local project environment storage.
- Supabase management service behavior.
- Supabase schema visualization.
- Superwall management service behavior.
- Builder integration tools, including backend deploy approvals and Superwall actions.
- App-store submission fact collection and export/publishing behavior.
- Eval suite loading and app session store behavior.

Coverage gaps for target 11x:

- No test yet proves app identity is `11x`.
- No test yet proves bundle ID is `app.kasey.11x`.
- No test yet proves app support path uses `11x`.
- No test yet proves Keychain namespace uses `app.kasey.11x`.
- No test yet proves URL scheme is `elevenx`.
- No test yet proves updater is disabled or non-vendor.
- No test yet proves the app boots without Supabase environment variables.
- No test yet proves the app boots without Superwall configuration.
- No test yet proves billing/credits/paywall UI is unreachable.
- No test yet proves local SQLite migrations and repositories work.
- No test yet proves local provider setup handles missing `OPENAI_API_KEY` as setup error rather than billing error.

## Deletion Candidates

Delete candidates for later passes:

- Supabase SDK dependency in `Package.swift` and Xcode project.
- Supabase config keys from plist, xcconfigs, and `Config.swift`.
- `SupabaseService`.
- `SupabaseManagementService`.
- `SupabaseManagementOAuthService`.
- `SupabaseSchemaVisualizer` unless converted to generated-project local analysis.
- Supabase auth use in `AuthManager`.
- Supabase session use in evals.
- Supabase management/build tools and bundled skill routing.
- Supabase logo assets.
- Superwall management service, state models, tool definitions, prompt routing, tests, and logo assets.
- Billing models, billing view model, billing views, billing tabs, billing deep links, checkout/portal/promo endpoints, and billing config flags.
- Credit gating headers and billing group/message preview tracking.
- Signup bonus/device fingerprint billing claim store.
- Hosted app-store page publish/unpublish and Supabase `published_app_store_pages` persistence.
- Hosted app URLs from app-store submission models.
- Sparkle updater runtime and release feed config unless replaced with owned 11x update channel.
- Hosted release publishing and Vercel deploy scripts unless reseated for 11x-owned release infrastructure.

## Reseat Candidates

Reseat candidates for later passes:

- App identity: rename to `11x`, bundle ID `app.kasey.11x`, URL scheme `elevenx`.
- Local single-user session/profile replacing Supabase auth.
- SQLite persistence with migration runner and repository boundary.
- Local filesystem asset storage under 11x app support.
- Provider adapter using `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL`.
- Keychain-backed provider secret storage under `app.kasey.11x`.
- Local diagnostics replacing credit/billing usage accounting.
- Local folder export and zip export replacing hosted deploy/publish.
- Local export-only app-store packet artifacts if still useful.
- Build and test commands after each pass-specific change.

## Hard Unknowns

- Current build/test status is unknown because Pass 01 did not run builds or tests.
- Exact SQLite schema needs field-by-field mapping during the persistence pass.
- Some generated-project guidance references Supabase, Superwall, StoreKit, Stripe, analytics, and hosted deployment; later passes must decide which are deleted versus retained only as generated-project examples.
- The safest sequencing for removing Sparkle depends on Pass 02 identity isolation and Pass 11 packaging decisions.
- Some tests currently assert legacy behavior and will need either deletion or replacement tests in the pass where that behavior is removed.

## Next Implementation Prompt

Read `AGENTS.md` first. Then read the authoritative 11x docs and `AUDIT_LOCALIZATION.md`. Begin Pass 02 only: isolate app identity to `11x`, bundle ID `app.kasey.11x`, URL scheme `elevenx`, and 11x-scoped app support/preferences/Keychain namespaces. Do not remove Supabase, Superwall, billing, hosted deploy, app-store submission, or Sparkle yet except where identity isolation requires disabling unsafe vendor updater behavior. Preserve user changes, run pass-specific verification, show `git status --short`, and do not push.

## Pass 02 Update - App Identity Isolation

Pass status: implemented.

Runtime scope:

- Changed app identity, local namespaces, and updater activation only.
- Did not remove Supabase, Superwall, billing, provider, storage, or SQL migration behavior.
- Did not implement Pass 03.
- Did not push.

Files changed for Pass 02:

- `AppInfo.plist`
- `10x-macos.xcodeproj/project.pbxproj`
- `10x-macos/10x_macos.entitlements`
- `10x-macos/Config.swift`
- `10x-macos/TenXAppApp.swift`
- `10x-macos/ContentView.swift`
- `10x-macos/Services/AppIdentity.swift`
- `10x-macos/Services/AppUpdateChannel.swift`
- `10x-macos/Services/AuthKeychainStore.swift`
- `10x-macos/Services/FileSystemWatcher.swift`
- `10x-macos/Services/LocalProjectStore.swift`
- `10x-macos/Services/ProjectKeychainStore.swift`
- `10x-macos/Services/SimulatorPreviewService.swift`
- `10x-macos/Services/SupabaseManagementOAuthService.swift`
- `10x-macos/Services/TenXKeychainAccessGroup.swift`
- `10x-macos/Services/XcodePreviewService.swift`
- `10x-macos/ViewModels/AuthManager.swift`
- `10x-macos/ViewModels/BillingViewModel.swift`
- `10x-evals/AppSessionStore.swift`
- `10x-evalsTests/AppSessionStoreTests.swift`
- `10x-macosTests/AppIdentityIsolationTests.swift`
- `10x-macosTests/AuthKeychainStoreTests.swift`

Identity changes completed:

- Display name changed to `11x`.
- Built product changed from `10x.app` to `11x.app`.
- Bundle identifier changed from `app.10x.macos` to `app.kasey.11x`.
- Custom URL scheme changed from `app.10x.macos` to `elevenx`.
- `asherlewis.online` was not used as a custom URL scheme.
- App support directory moved to `~/Library/Application Support/11x`.
- Explicit preferences keys now use the `app.kasey.11x` namespace.
- Keychain service namespace moved to `app.kasey.11x`.
- Keychain access group suffix moved to `app.kasey.11x.shared`.
- Temporary/cache-style preview directories moved from `TenXApp-*` to `ElevenX-*`.
- Sparkle auto-checking and auto-updating were disabled, and the configured Sparkle feed/public key were blanked.
- The app root now shows a visible local-mode badge: `11x`, `Single-user cockpit`, `Local backend`, `No billing`.

Tests/assertions added:

- `10x-macosTests/AppIdentityIsolationTests.swift`
- Assertions cover runtime identity constants, Info.plist display name and URL scheme, Xcode product/bundle settings, entitlements, disabled updater feed, and local-mode badge copy.

Verification run:

- `git diff --check` passed.
- `plutil -lint AppInfo.plist 10x-macos/10x_macos.entitlements 10x-macos/10x_macos_release.entitlements` passed.
- Static scan for active `app.10x.macos`, `app.10x.shared`, `Library/Developer/TenXApp`, and `downloads.example.invalid/appcast` found only negative assertions in `AppIdentityIsolationTests`.
- `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO` passed and produced `.derivedData/10x-macos/Build/Products/Debug/11x.app`.
- Built app Info.plist reported `CFBundleIdentifier=app.kasey.11x`, `CFBundleName=11x`, `CFBundleDisplayName=11x`, URL scheme `elevenx`, and `SUEnableAutomaticChecks=false`.
- `swift test --filter AppIdentityIsolationTests` failed before compilation because Swiftly could not locate `Swift 6.3.1`.
- `xcrun swift test --filter AppIdentityIsolationTests` passed: 6 tests, 0 failures.

Remaining identity-era notes:

- The Xcode project and source folder names still contain `10x-macos`; they are build target/repo structure names, not app bundle identity. They were left in place to avoid a large rename in Pass 02.
- SwiftPM package/module names still contain `TenXApp`; they were left in place to avoid cross-target rename churn in Pass 02.
- Generated app bundle IDs still use `com.10x.generated.*`; those identify generated iOS app artifacts, not the 11x macOS cockpit bundle. They were left for a later pass.
- Supabase, Superwall, billing, hosted app-store, and provider surfaces remain active legacy implementation targets for later passes.

## Pass 03 Update - Local Entitlements and Monetization Removal

Pass status: implemented.

Runtime scope:

- Replaced pricing, credits, billing, paywalls, checkout, receipt validation, StoreKit purchase flows, and Superwall with a local unlimited single-user entitlement model.
- Did not remove Supabase persistence/auth yet.
- Did not implement SQL migration yet.
- Did not implement provider reseat yet.
- Did not implement Pass 04.
- Did not push.

Files changed for Pass 03:

- `10x-macos/Models/LocalEntitlements.swift` (new)
- `10x-macosTests/LocalEntitlementsTests.swift` (new)
- `10x-macos/Config.swift`
- `10x-macos/Services/AppIdentity.swift`
- `10x-macos/Models/AppTab.swift`
- `10x-macos/Views/Settings/SettingsView.swift`
- `10x-macos/Views/Settings/GeneralSettingsView.swift`
- `10x-macos/Views/Settings/UsageSettingsView.swift`
- `10x-macos/ContentView.swift`
- `10x-macos/TenXAppApp.swift`
- `10x-macos/Views/HomeView.swift`
- `10x-macos/Views/Chat/ChatInputView.swift`
- `10x-macos/Views/Chat/ChatPanelView.swift`
- `10x-macos/Services/APIClient.swift`
- `10x-macos/Services/DeviceFingerprintService.swift`
- `10x-macos/Models/AppStoreReview.swift`
- `10x-macos/Models/ProductionGuide.swift`
- `10x-macos/Services/Builder/GenerationService.swift`
- `10x-macos/Theme.swift`
- `10x-macos/ViewModels/BuilderViewModel.swift`
- `10x-macos/ViewModels/BuilderViewModel+Generation.swift`
- `10x-macos/ViewModels/BuilderViewModel+Preview.swift`
- `10x-macos/ViewModels/BuilderViewModel+AppStoreSubmission.swift`
- `10x-macos/ViewModels/BuilderViewModel+Review.swift`
- `10x-macos/ViewModels/BuilderViewModel+Projects.swift`
- `10x-macos/Services/Builder/BuilderPrompts.swift`
- `10x-macos/Services/Builder/BuilderToolDefinitions.swift`
- `10x-macos/Services/Builder/BundledSkillsCatalog.swift`
- `10x-macos/Services/Builder/SkillsManager.swift`
- `10x-macos/Services/Builder/ToolExecutor.swift`
- `10x-macos/Models/BuilderProject.swift`
- `10x-macos/Models/ProjectIntegrations.swift`
- `10x-macos/Models/ProjectDependencies.swift`
- `10x-macos/Services/XcodePreviewService.swift`
- `10x-macos/Views/Preview/EnvironmentVariablesView.swift`
- `10x-macos/Models/OnboardingData.swift`
- `10x-macos/ViewModels/BillingViewModel.swift` (deleted)
- `10x-macos/Views/Billing/BillingView.swift` (deleted)
- `10x-macosTests/SuperwallManagementServiceTests.swift` (deleted)
- `10x-macosTests/AppIdentityIsolationTests.swift`
- `10x-macosTests/AppStoreSubmissionTests.swift`
- `10x-macosTests/AuthKeychainStoreTests.swift`
- `10x-macosTests/BuilderIntegrationToolTests.swift`
- `10x-macosTests/ProductionGuideTests.swift`
- `10x-macosTests/ProjectIntegrationSupportTests.swift`
- `10x-macosTests/XcodePreviewServiceTests.swift`

Entitlement changes completed:

- Added `LocalEntitlements.swift` as the single source of truth.
- `mode` is `single_user_unlimited`.
- `billingEnabled` is `false`.
- `creditsEnabled` is `false`.
- `creditsRemaining` is `Double.infinity`.
- `canGenerate` is `true`.
- `canExport` is `true`.
- `canUseLocalBackend` is `true`.
- `canUseHostedVendorBackend` is `false`.
- `canUseBilling` is `false`.
- `canPurchaseCredits` is `false`.
- `paymentsEnabled` is `false`.
- `signupBonusEnabled` is `false`.
- `billingTestMode` is `true` (billing is permanently off).
- `usageTrackingGatesFeatures` is `false`.
- `Config.paymentsEnabled`, `Config.signupBonusEnabled`, and `Config.billingTestMode` now delegate to `LocalEntitlements`.
- `AppIdentity.localBadgeDetails` now reads `Single-user cockpit`, `Unlimited local`, `No billing`.

Billing/pricing/credit/paywall removal completed:

- Deleted `BillingViewModel.swift` and `BillingView.swift`.
- Removed the `.billing` tab kind from `AppTab`.
- Removed the Billing section from `SettingsView` and the `BillingDisabledSettingsView`.
- Removed billing deep-link handling from `TenXAppApp` and `ContentView`.
- Removed billing environment injection from `ContentView`.
- Replaced the HomeView "plans and packs" card with a "Create your first project" card.
- Removed credit-gating and billing-upgrade CTAs from `ChatInputView` and `ChatPanelView`.
- Removed billing plan/subscription display from `GeneralSettingsView`.
- Replaced `UsageSettingsView` with a local-diagnostics-only view.
- Removed billing endpoints and credit-units header from `APIClient`.
- Removed billing fields from `AppStoreReview` model.
- Removed billing references from `ProductionGuide` and `OnboardingData`.
- Removed billing debug group IDs and message previews from generation/review flows (kept as optional local diagnostics metadata).
- Removed `Theme.billingStatusTint` active logic.

Superwall removal/disabling completed:

- Deleted `SuperwallManagementServiceTests.swift`.
- Removed Superwall from the bundled skill registry (`superwall` skill no longer advertised).
- Removed `superwall` from `BuilderToolDefinitions` integration tool groups.
- Stubbed `superwall_manage` tool execution to return "Superwall is not available in 11x local cockpit.".
- Removed Superwall prompt sections from `BuilderPrompts`.
- Removed Superwall dependency inference from `ProjectDependencies`.
- Removed `.superwall` integration case from active `ProjectIntegrations` switch paths.
- Removed Superwall package dependency injection from `XcodePreviewService`.
- Removed Superwall state from `BuilderProject` active settings key and decoding (kept inert property for compatibility).
- Stubbed `hasSuperwallRuntimeIntegration` to always return `false`.
- Removed Superwall state propagation in `BuilderViewModel+Projects`.
- Removed Superwall from `SkillsManager` skill descriptions and icons.
- The Superwall management service file and ProjectSuperwall model file remain in the tree as inert dead code; full deletion requires removing internal references across `ToolExecutor`, `BuilderViewModel+Generation`, and `EnvironmentVariablesView`, which is deferred to a later pass to avoid large cascading churn.

Tests/assertions added:

- `10x-macosTests/LocalEntitlementsTests.swift`
- 22 assertions covering mode, billing/credits flags, generation/export availability, hosted-vendor backend flag, payments/signup-bonus flags, billing test mode, usage-tracking non-gating, Config integration, app identity badge, and no-credit-blocking invariants.
- Removed or updated Superwall/billing assertions in `BuilderIntegrationToolTests`, `ProjectIntegrationSupportTests`, `XcodePreviewServiceTests`, `AppStoreSubmissionTests`, `AuthKeychainStoreTests`, `ProductionGuideTests`, and `AppIdentityIsolationTests`.

Verification run:

- `git diff --check` passed.
- `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO` passed and produced `.derivedData/10x-macos/Build/Products/Debug/11x.app`.
- `xcrun swift test` passed: 170 tests, 0 failures.
- `xcrun swift test --filter LocalEntitlementsTests` passed: 22 tests, 0 failures.
- Static scan confirmed no active runtime references to `BillingViewModel`, `BillingView`, `.billing` tab, `presentCatalog`, checkout flows, or credit-gating in `ChatInputView`/`ChatPanelView`/`HomeView`.
- Static scan confirmed Superwall SDK dependency is not in `Package.swift`; Superwall tool/skill references are stubbed/disabled at integration boundaries.

Remaining monetization-era notes:

- `BillingModels.swift` remains as a usage-diagnostics helper (`BillingDisplay`, `BillingMessageCharge`) for the local diagnostics usage list; it is not used for gating.
- `SuperwallManagementService.swift` and `ProjectSuperwall.swift` remain as inert files; no runtime path reaches them because the integration switch cases and tool catalog no longer expose Superwall.
- Supabase persistence/auth remains in place per Pass 03 scope lock.
- SQL migration and provider reseat remain future-pass work.

## Next Implementation Prompt

Read `AGENTS.md` first. Then read the authoritative 11x docs and `AUDIT_LOCALIZATION.md`. Begin Pass 04 only: provider reseat to OpenAI-compatible BYOK/local gateway using `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL`. Do not remove Supabase/Superwall persistence/auth beyond what Pass 03 already disabled. Preserve user changes, run pass-specific verification, show `git status --short`, and do not push.

## Pass 04 — Supabase to SQL Migration

### Pass Scope And Evidence

Pass: Pass 04 — remove Supabase as a runtime dependency and replace with local SQLite persistence.

Runtime behavior changed:

- Auth: no remote login required. `AuthManager` loads/creates a single local profile.
- Project/version/message metadata: stored in local SQLite (`cockpit.sqlite`) instead of Supabase tables.
- Supabase management tools: stubbed; all remote operations return `unavailableInLocalCockpit`.
- Supabase management OAuth: stubbed; no remote OAuth flow.
- Supabase Swift package dependency removed from `Package.swift`.

Files created in this pass:

- `PERSISTENCE_DECISION.md`
- `10x-macos/Services/DB/CockpitDatabase.swift`
- `10x-macos/Services/DB/MigrationSet.swift`
- `10x-macos/Services/DB/migrations/001_schema_migrations.sql`
- `10x-macos/Services/DB/migrations/002_local_profile.sql`
- `10x-macos/Services/DB/migrations/003_projects.sql`
- `10x-macos/Services/DB/migrations/004_versions.sql`
- `10x-macos/Services/DB/migrations/005_messages.sql`
- `10x-macos/Services/DB/migrations/006_app_settings.sql`
- `10x-macos/Services/DB/migrations/007_usage_logs.sql`
- `10x-macos/Services/DB/migrations/008_assets.sql`
- `10x-macos/Services/DB/Repositories/ProfileRepository.swift`
- `10x-macos/Services/DB/Repositories/ProjectRepository.swift`
- `10x-macos/Services/DB/Repositories/VersionRepository.swift`
- `10x-macos/Services/DB/Repositories/MessageRepository.swift`
- `10x-macos/Services/DB/Repositories/AppSettingsRepository.swift`
- `10x-macos/Services/DB/Repositories/UsageLogRepository.swift`
- `10x-macos/Services/DB/Repositories/AssetRepository.swift`
- `10x-macosTests/DB/CockpitDatabaseTests.swift`
- `10x-macosTests/NoSupabaseRuntimeTests.swift`

Files modified in this pass (material to Supabase removal):

- `Package.swift` — removed `supabase-swift` dependency and `Supabase` product link.
- `10x-macos/ViewModels/AuthManager.swift` — local profile auth; removed Supabase/OAuth/Apple sign-in.
- `10x-macos/Services/AuthKeychainStore.swift` — removed `KeychainAuthLocalStorage` (depended on Supabase `AuthLocalStorage`).
- `10x-macos/Services/SupabaseService.swift` — rewrote as local SQLite compatibility shim.
- `10x-macos/Services/SupabaseManagementService.swift` — stubbed remote management; kept minimal parsers/types for UI compatibility.
- `10x-macos/Services/SupabaseManagementOAuthService.swift` — stubbed remote OAuth.
- `10x-macos/Services/XcodePreviewService.swift` — removed Supabase dependency inference for generated projects.
- `10x-macos/Services/Builder/BundledSkillsCatalog.swift` — removed `import Supabase` from skill markdown content.
- `10x-macos/Views/Auth/LoginView.swift` — replaced Google sign-in button with local-cockpit entry.
- `10x-macosTests/AuthKeychainStoreTests.swift` — removed Supabase/Superwall token-store tests.
- `10x-macosTests/SupabaseManagementServiceTests.swift` — removed tests that required remote/token APIs.
- `10x-macosTests/XcodePreviewServiceTests.swift` — updated to assert Supabase dependency is absent.

Files archived or moved: none.

### Remaining Supabase* Types (Documented Compatibility Shims)

The following `Supabase*` symbols remain in active runtime code as temporary compatibility shims to avoid a large view-model/UI cascade in this pass. They do not import the Supabase SDK and do not perform remote calls:

- `SupabaseService` — temporary local SQLite shim. Routes project/version/message persistence to repositories.
- `SupabaseManagementService` — stubbed; only URL parsing and minimal JSON parsers remain.
- `SupabaseManagementOAuthService` — stubbed; no OAuth flow.
- `SupabaseSchemaVisualizer` — no Supabase import; reads local SQL files.
- `SupabaseManagementProject`, `SupabaseManagementOrganization`, `SupabaseProjectConnectionDetails`, `SupabaseAuthProviderSnapshot` — UI-bound types.
- `SupabaseReadTableInput`, `SupabaseWriteTableInput`, `SupabaseExecuteSQLInput`, `SupabaseManageSettingsInput`, `SupabaseWriteOperation`, `SupabaseManageSettingsAction` — tool input types.
- `SupabaseServiceError`, `SupabaseSessionSnapshot`, `SupabaseAuthEvent`, `SupabaseAuthStateUpdate` — `SupabaseService` compatibility types.
- `SupabaseManagementServiceError`, `SupabaseManagementOAuthError` — error types used by views.

### What Was Not Done (Scope Locks Honored)

- Provider reseat was not implemented beyond removing Supabase as a dependency.
- Hosted export changes were not implemented beyond what was required to remove Supabase dependency.
- No SQL migration tooling was added for importing legacy Supabase data.
- Superwall and billing surfaces were not touched beyond existing Pass 03 work.

### Verification

- `git diff --check` passed.
- `xcrun swift test` passed: 170 tests, 0 failures.
- `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO` succeeded and produced `.derivedData/10x-macos/Build/Products/Debug/11x.app`.
- `NoSupabaseRuntimeTests` confirms:
  - app boots without Supabase env vars
  - no runtime source file imports `Supabase`
  - `Package.swift` does not reference `supabase-swift`
- `CockpitDatabaseTests` confirms:
  - migrations apply on empty DB
  - project CRUD works through SQL
  - version persistence works through SQL
  - settings persistence works through SQL
  - usage logs are local diagnostics only and do not gate features

### Static Scan Notes

- No `import Supabase` remains in `10x-macos/`, `10x-evals/`, `10x-macosTests/`, or `10x-evalsTests/`.
- `Package.swift` no longer declares the `supabase-swift` package or the `Supabase` product dependency.
- Supabase env vars (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) still appear in `Config.swift` as inert fallbacks and in legacy project environment variable handling; they no longer drive auth or runtime persistence.

## Pass 05 — Local Filesystem Asset Storage

### Pass Scope And Evidence

Pass executed: Pass 05 only, local filesystem asset storage.

Runtime behavior changed:

- Added `LocalAssetStorage`, rooted by default at `AppIdentity.appSupportDirectory/assets`.
- New uploaded attachments, generated review assets, preview screenshots, captured screenshots, thumbnails, and custom project icons now write bytes to the local asset filesystem and save metadata through `AssetRepository`.
- Asset paths stored in SQLite are relative paths under the asset root, using `projects/<project_id>/...` layout.
- `AssetRepository` now validates relative asset paths before persisting metadata and filters soft-deleted assets.
- Existing legacy `tenx/` asset paths remain readable as fallback for offline reload compatibility.
- Path traversal, absolute paths, home-relative paths, URL-style paths, backslashes, and NUL-containing paths are rejected before filesystem access.

Files created:

- `10x-macos/Services/LocalAssetStorage.swift`
- `10x-macos/Services/DB/migrations/009_assets_deleted_at.sql`
- `10x-macosTests/DB/LocalAssetStorageTests.swift`

Files modified:

- `10x-macos/Services/DB/MigrationSet.swift`
- `10x-macos/Services/DB/Repositories/AssetRepository.swift`
- `10x-macos/Services/LocalProjectStore.swift`
- `10x-macos/ViewModels/BuilderViewModel+Preview.swift`
- `10x-macos/ViewModels/BuilderViewModel+Review.swift`

### Inventory Findings

Existing local asset/storage paths inventoried:

- `LocalProjectStore` attachments under legacy `tenx/chats/<chat_id>/messages/<message_id>/attachments/`.
- `LocalProjectStore` preview screen, captured screen, review asset, thumbnail, and custom icon storage.
- `BuilderViewModel+Preview` preview and captured-screen path creation.
- `BuilderViewModel+Review` app-review icon and screenshot path creation.
- `AssetRepository`, `008_assets.sql`, and SQLite migration registration.
- `BuilderAttachmentImporter` attachment import path behavior.
- Static scan for hosted storage strings, bucket references, and asset path call sites.

Remaining hosted/cloud storage assumptions found:

- `10x-macos/Services/Builder/BundledSkillsCatalog.swift` still contains generated-app guidance mentioning Supabase storage buckets.
- `10x-macos/Services/Builder/BuilderToolDefinitions.swift` still contains tool-description examples around `storage.buckets`.
- `10x-macosTests/BuilderIntegrationToolTests.swift` and `10x-macosTests/ProjectIntegrationSupportTests.swift` still assert generated-app Supabase storage guidance.
- Xcode project resolution still includes the Supabase package in the build graph as a pre-existing project-file lag from Pass 04; the active SwiftPM manifest no longer declares Supabase.

Those remaining findings were inventoried but not broadly removed in Pass 05 because this pass is limited to local 11x asset persistence and asset portability hooks.

### Verification

- `git diff --check` passed.
- `xcrun swift test --filter LocalAssetStorageTests` passed: 5 tests, 0 failures.
- `xcrun swift test --filter 'LocalAssetStorageTests|CockpitDatabaseTests|LocalProjectStoreEnvironmentTests|AppIdentityIsolationTests'` passed: 18 tests, 0 failures.
- `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO` passed and produced `.derivedData/10x-macos/Build/Products/Debug/11x.app`.
- Static inventory scan confirmed the new local asset paths and the remaining generated-app Supabase bucket guidance listed above.

### Remaining Notes

- Full hosted export/deploy replacement was not implemented in this pass.
- Provider reseat was not started.
- Chat message JSON still retains inline attachment payload data for existing UI/model-context behavior; filesystem materialization is now routed through local asset storage for new files.
- Legacy `tenx/` state/index JSON remains local UI metadata for compatibility; new asset bytes are rooted under `assets/`.
- Export inclusion of required assets remains a later-pass requirement; Pass 05 only establishes portable local paths and metadata hooks.

## Pass 06 — OpenAI-Compatible Provider Reseat

### Pass Scope And Evidence

Pass executed: Pass 06 only, OpenAI-compatible provider reseat.

Runtime behavior changed:

- Generation calls no longer go through a vendor backend `/builder/claude/stream` proxy.
- `GenerationService` now uses an injected `OpenAIProviderAdapter` that calls the user-configured OpenAI-compatible endpoint directly.
- `BuilderContextManager.countTokens` no longer depends on a backend `/builder/claude/count-tokens` endpoint; it returns a local approximation.
- Provider metadata (`baseURL`, `model`) is stored in SQLite `provider_configs`.
- Provider secrets (`OPENAI_API_KEY`) are stored in the OS keychain via `ProviderKeychainStore`.
- `Config` exposes `OPENAI_API_KEY`, `OPENAI_BASE_URL`, and `OPENAI_MODEL` as provider env/config keys.
- `ProjectIntegrations` exposes `OPENAI_API_KEY` as a hosted (secret) field and `OPENAI_BASE_URL`/`OPENAI_MODEL` as client fields, with guidance updated for local/keychain storage.

Files created:

- `10x-macos/Services/Provider/ProviderConfig.swift`
- `10x-macos/Services/Provider/ProviderKeychainStore.swift`
- `10x-macos/Services/Provider/ProviderConfigRepository.swift`
- `10x-macos/Services/Provider/OpenAIProviderAdapter.swift`
- `10x-macos/Services/DB/migrations/010_provider_configs.sql`
- `10x-macosTests/Provider/OpenAIProviderAdapterTests.swift`
- `10x-macosTests/Provider/OpenAIProviderURLProtocolStub.swift`
- `10x-macosTests/Provider/ProviderConfigRepositoryTests.swift`
- `10x-macosTests/Provider/GenerationServiceProviderTests.swift`

Files modified:

- `10x-macos/Config.swift`
- `10x-macos/Models/ProjectIntegrations.swift`
- `10x-macos/Services/Builder/GenerationService.swift`
- `10x-macos/Services/Builder/BuilderContextManager.swift`
- `10x-macos/Services/DB/MigrationSet.swift`
- `10x-macosTests/ProjectIntegrationSupportTests.swift`
- `AGENTS.md` and `CLAUDE.md` (GitNexus index stats updated by `npx gitnexus analyze`)

### Inventory Findings

Existing provider assumptions inventoried:

- `GenerationService` called `APIClient.builder("claude/stream")` and parsed Anthropic NDJSON events.
- `BuilderContextManager.countTokens` called `APIClient.builder("claude/count-tokens")`.
- `Config` lacked `OPENAI_BASE_URL` and `OPENAI_MODEL`; `API_BASE_URL` defaulted to `http://localhost:8000`.
- `ProjectIntegrations` exposed only `OPENAI_API_KEY` with Supabase-flavored guidance.
- No provider adapter boundary existed; no SQL table held provider metadata; no keychain namespace existed for provider secrets.
- Request/response logs used `[billing-debug]` prefixes tied to credit-group semantics.

Remaining vendor-provider runtime assumptions not removed in Pass 06:

- Supabase management/auth code still exists in `10x-macos/Services/Supabase*` and `10x-macos/ViewModels` (to be removed in Pass 07 per master plan).
- `EvalRunner` still attempts Supabase token refresh (eval harness, not the macOS app runtime).
- Some tests still assert Supabase-specific behavior where those components are not yet removed.
- `APIClient` remains in place for other (non-provider) legacy API surfaces; it was not modified because impact analysis showed CRITICAL blast radius (165 symbols).

### Verification

- `git diff --check` passed.
- `xcrun swift test` passed: 185 tests, 0 failures.
- `xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO` passed and produced `.derivedData/10x-macos/Build/Products/Debug/11x.app`.
- Pass-specific tests added and passing:
  - `OpenAIProviderAdapterTests`: custom base URL, invalid base URL setup error, missing API key setup error, mocked streaming text and tool call, no hardcoded vendor endpoint.
  - `ProviderConfigRepositoryTests`: config persistence in SQLite, API key keychain storage, public metadata excludes secrets, validated config requires key.
  - `GenerationServiceProviderTests`: generation uses mocked OpenAI-compatible adapter, not credits or vendor backend.

### Remaining Notes

- Full removal of Supabase/Superwall/billing code remains a later pass (Pass 07 per master plan).
- `APIClient` was intentionally left untouched except for its continued use by non-provider legacy surfaces.
- The provider adapter currently assumes OpenAI-compatible SSE streaming. Tool/function calling support is preserved by mapping Anthropic-style tool definitions to OpenAI `tools`/`function` schema.

### Commit

- `reseat(provider): add openai-compatible adapter` (commit `7854822`)
- 19 files changed, 1407 insertions(+), 213 deletions(-)
- `git diff --check` passed before commit.
- No push performed.
