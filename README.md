# 11x

## What 11x Is

11x is an unlimited single-user local cockpit fork of the original 10x macOS app builder.

It is local-first, SQLite-backed, and designed to run as a separate user-owned macOS app. Project metadata lives in a local SQLite database, project assets live on the local filesystem, provider access uses an OpenAI-compatible BYOK or local-gateway adapter, and usage tracking is local diagnostics only.

11x does not require Supabase at runtime. It does not use Superwall. It does not include billing, credits, paywalls, checkout, receipt validation, hosted vendor deploy, or vendor App Store submission automation.

## Relationship to Original 10x

This repository started as a fork of the original 10x source.

The downloaded or vendor 10x DMG is a reference artifact only. It is not modified, patched, unpacked, resigned, overwritten, or depended on by this repository.

11x builds as a separate app with its own app name, bundle identifier, URL scheme, app support directory, preferences namespace, and Keychain namespace.

## Runtime Differences from the Vendor 10x DMG

| Surface | Vendor 10x package | 11x current repository state |
|---------|--------------------|------------------------------|
| App name | 10x | `11x` |
| Bundle ID | Vendor 10x bundle identity | `app.kasey.11x` |
| URL scheme | Vendor 10x scheme | `elevenx` |
| App support directory | Vendor 10x app support namespace | `~/Library/Application Support/11x` |
| Auth model | Remote/vendor auth | Local profile, no remote login required |
| Database | Hosted/vendor persistence | SQLite `cockpit.sqlite` |
| Asset storage | Hosted or vendor-oriented assumptions | Local filesystem under app support |
| Provider access | Vendor backend/provider proxy | OpenAI-compatible adapter |
| Secrets | Vendor/account-backed secrets | Keychain first, backend/local-only encrypted config second, environment variables only as a development fallback |
| Entitlements | Vendor/account entitlement model | `single_user_unlimited` |
| Billing | Vendor billing/subscription flow | Disabled/removed |
| Credits | Vendor credit accounting and gates | Disabled/removed |
| Superwall | Vendor monetization integration | Removed or stubbed inert where compatibility requires |
| Supabase | Vendor auth/database/management dependency | No runtime SDK/dependency; remaining Supabase-named code is compatibility or dead-code cleanup only |
| Hosted deploy | Vendor hosted deploy/publish paths | Disabled/replaced with local export |
| Hosted app pages | Hosted legal/support/app pages | Reframed as local artifacts only |
| App Store submission | Vendor submission automation | Disabled/reframed as local artifact/export only |
| Marketing generation | Vendor/backend marketing asset generation | Removed or blocked in local mode |
| Updater/Sparkle feed | Vendor updater feed | Feed/public key empty and automatic checks disabled |
| Usage tracking | Billing/credit accounting | Local diagnostics only, never gating |
| Export model | Hosted publishing and release automation | Local folder export plus zip export |

## Architecture Overview

```text
SwiftUI macOS app
  -> local app services
  -> SQLite repositories
  -> local filesystem assets
  -> OpenAI-compatible provider adapter
  -> OS Keychain for secrets
```

Core source areas:

- `10x-macos/`: macOS app source.
- `10x-macos/Services/DB/`: SQLite connection, migrations, and repositories.
- `10x-macos/Services/Provider/`: OpenAI-compatible provider configuration, key storage, and adapter code.
- `10x-macos/Services/LocalAssetStorage.swift`: local asset filesystem storage.
- `10x-macosTests/`: app regression tests for identity, local entitlements, persistence, provider behavior, local export, and forbidden runtime dependencies.

## Local-First Runtime Model

11x is built around a single local user profile. It should boot without Supabase credentials, without a vendor login, and without billing setup.

The local runtime model is:

- Local profile/session instead of remote auth.
- SQLite repositories instead of hosted database tables.
- Local filesystem assets instead of hosted object storage.
- OpenAI-compatible provider configuration instead of vendor model credits.
- Local diagnostics instead of usage gates.
- Local folder and zip export instead of hosted deployment.

## App Identity

Current locked identity:

| Field | Value |
|-------|-------|
| App name | `11x` |
| Bundle ID | `app.kasey.11x` |
| URL scheme | `elevenx` |
| App support directory name | `11x` |
| Preferences namespace | `app.kasey.11x` |
| Keychain namespace | `app.kasey.11x` |
| Optional Universal Links domain | `asherlewis.online` |
| Optional Universal Links prefix | `/11x/` |

The Xcode project and scheme names may still include `10x-macos`; those are source/build-system names, not the final built app identity.

## Persistence

11x uses SQLite.

- Database filename: `cockpit.sqlite`
- Default location: `~/Library/Application Support/11x/`
- Migrations: `10x-macos/Services/DB/migrations/`
- Migration tracking table: `schema_migrations`

Repository coverage includes local profile, projects, versions, messages, app settings, usage diagnostics, assets, and provider configuration.

## Asset Storage

Asset bytes are stored on the local filesystem under the 11x app support directory, usually below:

```text
~/Library/Application Support/11x/assets/
```

Asset metadata is stored in SQLite through `AssetRepository`. Paths are relative under the asset root, using project-scoped paths such as `projects/<project_id>/...`. Path traversal, absolute paths, URL-style paths, home-relative paths, and invalid path forms are rejected before filesystem access.

Legacy local `tenx/` asset paths may remain readable for offline compatibility.

## Provider Configuration

11x uses an OpenAI-compatible provider adapter. The provider configuration keys are:

| Variable | Purpose |
|----------|---------|
| `OPENAI_API_KEY` | Provider API key. Store in Keychain for normal app use. Environment fallback is for development only. |
| `OPENAI_BASE_URL` | OpenAI-compatible base URL. Defaults to `https://api.openai.com` when not set. |
| `OPENAI_MODEL` | Model name. Defaults to the repo's configured model when not set. |

`OPENAI_BASE_URL` can point to OpenAI-compatible providers such as local gateways, Ollama-compatible gateways, vLLM, OpenRouter, OpenAI-compatible proxies, or OpenAI itself.

API keys must not be committed. Provider status may show that a key is present or missing, but raw key material must not be surfaced in UI state, exported artifacts, logs, or documentation.

## Entitlements and Billing

11x uses a local entitlement source of truth:

```text
single_user_unlimited
```

Generation and export are allowed locally. Billing, credits, hosted vendor backend entitlement checks, checkout, subscription, receipt validation, and paywall gates are disabled or removed.

Usage records are local diagnostics only and must never gate generation, export, or app access.

## Hosted Features Removed or Disabled

The local cockpit does not depend on:

- Supabase auth, database, storage, realtime, edge functions, or SDK imports.
- Superwall runtime integration.
- Vendor billing, pricing, credits, subscriptions, checkout, or invoices.
- Vendor provider proxy endpoints for generation.
- Hosted app pages for legal/support/review assets.
- Vendor updater feeds.
- Vendor hosted deploy.

Remaining legacy names are documented below as compatibility shims or cleanup candidates.

## App Store / Marketing / Publishing Flows

11x does not provide vendor App Store submission automation.

Review, production, and submission surfaces that remain in the app are local/export-oriented artifacts. They may help inspect or export local metadata, but they do not publish hosted pages, submit to App Store Connect, run vendor marketing generation, or deploy through vendor infrastructure.

Release scripts under `scripts/release/` may still contain signing, notarization, Sparkle, hosted-site, or historical vendor release assumptions. They are not the default local verification path for 11x.

## Local Export

11x replaces hosted deploy with local export:

- Local folder export.
- Zip export.
- Export metadata that excludes provider secrets.
- Local assets included where required for rebuild or review.
- No login, credits, billing, hosted backend, or vendor deployment required.

The local debug zip sanity artifact from the reseat was:

```text
.derivedData/10x-macos/Build/Products/Debug/11x-debug-local.zip
```

## Security and Secret Handling

Secret handling priority:

1. OS Keychain.
2. Backend/local-only encrypted config, if needed.
3. Environment variables as a development fallback only.

Rules:

- Do not commit API keys or local `.env` files.
- Do not expose raw provider keys in UI state.
- Do not include provider secrets in local exports or zip archives.
- Keep provider metadata, key presence, and status separate from raw secret values.
- Keep vendor credentials out of the app runtime and out of release artifacts.

## Build Requirements

Expected local build environment:

- macOS with Xcode command line tools.
- Swift toolchain available through Xcode.
- Xcode project: `10x-macos.xcodeproj`.
- Scheme: `10x-macos`.

The validated no-signing app build (Lane 1) uses `CODE_SIGNING_ALLOWED=NO` and outputs `11x.app`.

Signed Release builds (Lane 2) and notarized release builds (Lane 3) require the
`Developer ID Application: Kasey Upton (S58MT4ATKM)` certificate and the `11x-notary`
keychain profile (Lane 3 only). See `BUILD_LANES.md`.

## Build Lanes

11x has three distinct build lanes. Do not confuse them.

| Lane | Script | Purpose |
|------|--------|---------|
| 1 — Fast unsigned verification | `./scripts/build-lanes/verify-unsigned.sh` | CI/dev sanity; fastest compile check; no distribution |
| 2 — Signed local Release build | `./scripts/build-lanes/build-signed-release.sh` | Hardened-runtime signed Release app for local testing or pre-notarization input |
| 3 — Notarized Developer ID release | `./scripts/release/build-notarized-11x.sh` | Public Gatekeeper-approved release zip (authoritative release lane) |

See `BUILD_LANES.md` for full lane definitions, expected outputs, and common mistakes.

## Build and Test Commands

Run SwiftPM tests:

```bash
xcrun swift test
```

Fast unsigned verification build (Lane 1):

```bash
./scripts/build-lanes/verify-unsigned.sh
```

Signed local Release build (Lane 2):

```bash
./scripts/build-lanes/build-signed-release.sh
```

Notarized Developer ID release build (Lane 3):

```bash
./scripts/release/build-notarized-11x.sh
```

Run the default forbidden runtime audit:

```bash
./scripts/forbidden-audit
```

Print legacy cleanup inventory:

```bash
./scripts/forbidden-audit --inventory
```

## Running the App Locally

Build first (Lane 1 — unsigned verification):

```bash
./scripts/build-lanes/verify-unsigned.sh
```

Open the built app:

```bash
open .derivedData/10x-macos/Build/Products/Debug/11x.app
```

The app should present itself as `11x`, use bundle ID `app.kasey.11x`, and run without requiring Supabase, Superwall, billing, credits, or a vendor login.

## Configuration Reference

Primary local provider configuration:

| Key | Required for generation | Notes |
|-----|-------------------------|-------|
| `OPENAI_API_KEY` | Yes | Store in Keychain for normal app use. Environment variable is development fallback only. |
| `OPENAI_BASE_URL` | No | OpenAI-compatible endpoint. Defaults to `https://api.openai.com`. |
| `OPENAI_MODEL` | No | Model name. Defaults to the configured repo fallback. |

Legacy or inert config keys may still appear in build files for compatibility or cleanup tracking, including empty Supabase placeholders and disabled updater settings. They should not be required for launching or using the local cockpit.

## Verification and Audit Commands

Use these as the main local proof surfaces:

```bash
git status --short
git diff --check
./scripts/forbidden-audit
./scripts/forbidden-audit --inventory
xcrun swift test
xcodebuild -project 10x-macos.xcodeproj -scheme 10x-macos -configuration Debug -derivedDataPath .derivedData/10x-macos build CODE_SIGNING_ALLOWED=NO
```

Useful identity checks after a build:

```bash
plutil -p .derivedData/10x-macos/Build/Products/Debug/11x.app/Contents/Info.plist
find .derivedData/10x-macos/Build/Products/Debug/11x.app -iname '*supabase*' -o -iname '*superwall*'
```

Default `./scripts/forbidden-audit` is the active-runtime authority. `./scripts/forbidden-audit --inventory` reports retained legacy cleanup candidates and is intentionally not a failure mode unless run with `--strict`.

## Known Compatibility Shims / Legacy Names

The repository still contains some legacy names. They are documented here so they are visible, not hidden.

- `SupabaseService` may remain as a local SQLite compatibility shim.
- `SupabaseManagementService` and `SupabaseManagementOAuthService` may remain as unavailable/local-cockpit stubs.
- `SupabaseSchemaVisualizer` and Supabase-named tool input/status models may remain as compatibility or generated-app artifact code.
- `SuperwallManagementService`, `ProjectSuperwall`, and related tool/status names may remain as inert dead-code cleanup candidates.
- Legacy test names or inventory warnings may mention Supabase or Superwall.
- `billingGroupId` and `billingMessagePreview` may still appear in provider/generation logs or local diagnostics as legacy naming; they should be renamed in a later cleanup pass if still present.
- `BillingModels.swift` may remain for retained local diagnostics display helpers.
- `10x-macos`, `TenXApp`, and related project/scheme/module names may remain as source/build-system names even though the built app is `11x`.
- `scripts/release/` may still contain historical signing, notarization, Sparkle, hosted-download, or release-site assumptions.

Use `./scripts/forbidden-audit` for active-runtime safety. Use `./scripts/forbidden-audit --inventory` to find legacy cleanup candidates.

## Non-Goals

This repository state is not trying to:

- Patch, modify, unpack, resign, overwrite, or depend on the vendor 10x DMG.
- Reintroduce Supabase as a runtime dependency.
- Reintroduce Superwall.
- Reintroduce billing, credits, paywalls, checkout, receipt validation, or StoreKit purchase flows for 11x.
- Provide vendor hosted deploy.
- Provide vendor App Store submission automation.
- Publish hosted legal/support/app pages.
- Ship a signed or notarized public release from the no-signing debug build.
- Remove every legacy-named compatibility shim in the same step as runtime reseating.

## Development Workflow

Recommended workflow:

1. Start with `git status --short`.
2. Keep changes narrowly scoped.
3. Do not modify the vendor DMG.
4. Do not commit secrets, `.env.local`, generated build products, or local app data.
5. Run `git diff --check`.
6. Run `./scripts/forbidden-audit`.
7. Run `xcrun swift test`.
8. Run the unsigned Xcode build when the change could affect app integration.
9. Review `git status --short` before committing.
10. Do not push unless explicitly instructed.

Commits are acceptable after verification succeeds. Pushing is not part of the default workflow.

## Troubleshooting

If `swift test` fails because Swiftly cannot locate the pinned Swift toolchain, use:

```bash
xcrun swift test
```

If signing verification fails on a local debug build, confirm whether the app was built with:

```bash
CODE_SIGNING_ALLOWED=NO
```

Strict `codesign` and `spctl` failures are expected for that unsigned debug build.

If something still says `10x`, check whether it is a source/build-system name such as `10x-macos`, a historical archive under `docs/archive/`, or a cleanup candidate. The built app identity should still be `11x`.

If something mentions Supabase or Superwall, run:

```bash
./scripts/forbidden-audit
./scripts/forbidden-audit --inventory
```

The default audit must pass. Inventory warnings are expected for retained legacy cleanup candidates.

If provider generation fails, check provider setup first: key present, base URL valid, model configured, and no raw secret exposed in logs or exports.

## License / Upstream Notice

This repository is a fork of the original 10x source and is currently documented as the 11x local cockpit target. Preserve applicable upstream notices and see `LICENSE` for the repository license.
