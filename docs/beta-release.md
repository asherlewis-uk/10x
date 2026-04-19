# Release Channel Workflow

This repo ships **10x.app** as a notarized DMG outside the Mac App Store with two Sparkle channels:

The open-source repo uses placeholder domains and updater keys in source control. Replace them with
your own values before publishing binaries.

- `stable`: default channel, canonical feed item, build `9000`
- `beta`: opt-in channel, Sparkle channel `beta`, builds `1...8999`

## Local Commands

From the `10x-macos/` repo root:

```bash
./scripts/release/build-release.sh 1.0.0 1 beta
./scripts/release/create-dmg.sh 1.0.0 1 beta
./scripts/release/verify-release.sh 1.0.0 1 beta
./scripts/release/publish-release.sh 1.0.0 1 beta

./scripts/release/build-release.sh 1.0.0 9000 stable
./scripts/release/create-dmg.sh 1.0.0 9000 stable
./scripts/release/verify-release.sh 1.0.0 9000 stable
./scripts/release/publish-release.sh 1.0.0 9000 stable
```

If Apple credentials are available, add:

```bash
export APPLE_TEAM_ID=YOURTEAMID
export DEV_ID_APP_CERT_NAME="Developer ID Application: Example, Inc. (YOURTEAMID)"
export NOTARY_KEYCHAIN_PROFILE=tenx-notary

./scripts/release/notarize-dmg.sh 1.0.0 1 beta
```

One-time setup helpers:

```bash
./scripts/release/import-developer-id-cert.sh /path/to/developer-id.p12 'p12-password'
./scripts/release/store-notary-credentials.sh /path/to/AuthKey_ABC123XYZ.p8 ABC123XYZ 00000000-0000-0000-0000-000000000000 YOURTEAMID
./scripts/release/export-sparkle-private-key.sh
./scripts/release/deploy-vercel.sh /path/to/published-site-root
```

## Required Environment Variables

- `APP_VERSION` and `APP_BUILD`: accepted as script args or env
- `APPLE_TEAM_ID`: required for signed export
- `DEV_ID_APP_CERT_NAME`: required for DMG signing and notarization
- `APPLE_DEVELOPER_ID_PROFILE_BASE64`: optional in CI; only needed if the release build adds a Developer ID-restricted entitlement later
- `NOTARY_KEYCHAIN_PROFILE`: required for `notarytool submit`
- `DOWNLOADS_ROOT`: optional override for the publish destination
- `SPARKLE_PRIVATE_KEY_BASE64`: required in CI for signing the Sparkle enclosure
- `VERCEL_TOKEN`: required in CI or local shell for `deploy-vercel.sh`
- `VERCEL_PROJECT_ID`: required in CI or local shell for `deploy-vercel.sh`
- `VERCEL_ORG_ID`: required in CI or local shell for `deploy-vercel.sh`
- `SPARKLE_KEYCHAIN_ACCOUNT`: optional Sparkle keychain account name, defaults to `10x-app-builder`

Optional advanced env:

- `SIGNING_KEYCHAIN`: custom keychain for `codesign`
- `NOTARY_KEYCHAIN`: custom keychain for `notarytool`
- `DIST_BASE_URL`: defaults to `https://downloads.example.invalid`
- `DOWNLOAD_URL_OVERRIDE`: overrides the enclosure URL written into `appcast.xml`
- `RELEASE_NOTES_URL_OVERRIDE`: overrides the browser release notes URL written into `latest.json`
- `SPARKLE_RELEASE_NOTES_URL_OVERRIDE`: overrides the standalone HTML release notes URL written into `appcast.xml`
- `PUBLISH_DMG_COPY=0`: skip copying the DMG into the publish folder when hosting the binary elsewhere
- `SPARKLE_PRIVATE_KEY_FILE`: file path alternative to `SPARKLE_PRIVATE_KEY_BASE64`
- `RELEASE_NOTES_PATH`: custom HTML file to publish instead of the generated placeholder
- `VERCEL_SCOPE`: optional Vercel team/account slug if you want `deploy-vercel.sh` to pass `--scope`

## Outputs

Local build artifacts land under:

```text
build/release/stable/<version>/
build/release/beta/<version>-beta.<build>/
```

Published channel artifacts land under:

```text
build/release/published-site/stable/
build/release/published-site/beta/
```

## GitHub Actions

The workflow scaffolds live at:

- `.github/workflows/release-beta.yml`
- `.github/workflows/release-stable.yml`
- `.github/workflows/release-channel.yml`

- Beta `workflow_dispatch` expects `version` and `build`
- Stable `workflow_dispatch` expects `version` and always uses build `9000`
- Beta tag builds expect `beta/v<semver>-beta.<build>`
- Stable tag builds expect `v<semver>`
- Beta build numbers must increase monotonically within a version
- Stable versions must increase monotonically and cannot reuse the same semver
- After `vX.Y.Z` stable is live, do not keep publishing `X.Y.Z-beta.N`; those beta builds are numerically lower than the stable build and Sparkle cannot move stable installs onto them
- The next beta after stable `vX.Y.Z` should use a higher semver such as `X.Y.(Z+1)-beta.1`
- If signing or notarization secrets are missing, the workflow exits immediately with a clear error
- `APPLE_DEVELOPER_ID_PROFILE_BASE64` is optional for the current beta DMG because the app uses Apple web OAuth and does not ship the native Sign in with Apple entitlement
- Add repository secrets named `VERCEL_TOKEN`, `VERCEL_PROJECT_ID`, and `VERCEL_ORG_ID`
- The workflows publish the signed DMG, channel metadata, and Sparkle feeds to Vercel
- Create a Vercel project with no Git integration and attach the custom domain `downloads.example.invalid`
- The canonical live update feed is `https://downloads.example.invalid/appcast.xml`
- Beta compatibility updates remain available at `https://downloads.example.invalid/beta/appcast.xml`

Release notes can now be supplied per build at:

```text
scripts/release/release-notes/<version>.html
scripts/release/release-notes/<version>-beta.<build>.html
```

Stable releases use `<version>.html`. Beta releases first look for `<version>-beta.<build>.html` and then fall back to:

```text
scripts/release/release-notes/<version>.html
```

Recommended authoring rule:

- Put shared, user-facing product notes in `<version>.html`.
- Only create `<version>-beta.<build>.html` when a specific beta needs temporary tester guidance, known issues, or rollout caveats that should not ship to stable.
- Avoid hardcoding beta build numbers in shared prose so the same notes can ship cleanly in a later stable release.

## Apple-Blocked Steps

- Importing a `Developer ID Application` certificate
- Creating or downloading the Developer ID provisioning profile for `app.10x.macos`
- Exporting a signed `developer-id` app
- Notarizing the DMG with `notarytool`
- Stapling and Gatekeeper validation of the final shipped DMG
