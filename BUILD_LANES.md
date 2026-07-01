# 11x Build Lanes

This document defines the three supported 11x macOS build lanes. Future agents
must use the correct lane for the task at hand and must not confuse the fast
unsigned verification build with signed or notarized release builds.

## Product identity (locked)

| Field | Value |
|-------|-------|
| App name | `11x` |
| Bundle ID | `app.kasey.11x` |
| URL scheme | `elevenx` |
| Team ID | `S58MT4ATKM` |
| Developer ID Application identity | `Developer ID Application: Kasey Upton (S58MT4ATKM)` |
| Notary keychain profile | `11x-notary` |

Historical 10x-era names (`10x-macos` project/scheme, `TenXApp` module) remain
as build-system identifiers only. The built app identity is always 11x.

---

## Lane 1 — Fast unsigned verification

**Purpose:** CI/dev sanity. Fastest compile check. Does not produce a
distributable app.

**When to use:**
- Local development iteration.
- SwiftPM/Xcode integration checks.
- Before committing code that touches the macOS app target.

**When not to use:**
- Do not use for release packaging.
- Do not use for Gatekeeper/codesign acceptance tests.
- Do not distribute the produced app.

**Command:**

```bash
./scripts/build-lanes/verify-unsigned.sh
```

Equivalent raw `xcodebuild`:

```bash
xcodebuild -project 10x-macos.xcodeproj \
  -scheme 10x-macos \
  -configuration Debug \
  -derivedDataPath .derivedData/10x-macos \
  build CODE_SIGNING_ALLOWED=NO
```

**Expected output:**
- `.derivedData/10x-macos/Build/Products/Debug/11x.app`
- `** BUILD SUCCEEDED **`
- `CFBundleDisplayName`: `11x`
- `CFBundleIdentifier`: `app.kasey.11x`
- URL scheme: `elevenx`
- No Supabase/Superwall artifacts inside the bundle.

**Expected failures (do not treat as blockers):**
- `codesign --verify --deep --strict` fails.
- `spctl -a -vvv -t execute` fails.

These are expected because the build was produced with `CODE_SIGNING_ALLOWED=NO`.

---

## Lane 2 — Signed local Release build

**Purpose:** Produce a hardened-runtime-signed Release app for local testing,
ad-hoc distribution, or as input to a separate notarization step. This lane does
not submit to Apple notarization and therefore does not produce a public
Gatekeeper-approved distributable on its own.

**When to use:**
- Local Release testing with a valid Developer ID certificate.
- Validating the full signing chain before notarization.
- Preparing an app bundle that another tool will notarize.

**When not to use:**
- Do not use for fast compile checks (use Lane 1).
- Do not distribute to users without notarization (use Lane 3).

**Requirements:**
- Developer ID Application certificate for `Developer ID Application: Kasey Upton (S58MT4ATKM)` installed in the default keychain.
- Internet access for `--timestamp`.

**Command:**

```bash
./scripts/build-lanes/build-signed-release.sh
```

**Expected output:**
- `.derivedData/11x-signed/Build/Products/Release/11x.app`
- `** BUILD SUCCEEDED **`
- `codesign --verify --deep --strict` passes.
- `Identifier=app.kasey.11x`
- `Authority=Developer ID Application: Kasey Upton (S58MT4ATKM)`
- `TeamIdentifier=S58MT4ATKM`
- `Runtime Version=...` present.
- `com.apple.security.get-task-allow` is absent.
- `spctl -a -vvv -t execute` reports:
  - `source=Unnotarized Developer ID`
  - `origin=Developer ID Application: Kasey Upton (S58MT4ATKM)`

The `spctl` rejection is expected because this lane does not notarize.

**Environment overrides:**
- `DEVELOPMENT_TEAM` — defaults to `S58MT4ATKM`.
- `CODE_SIGN_IDENTITY` — defaults to `Developer ID Application: Kasey Upton (S58MT4ATKM)`.
- `DERIVED_DATA` — defaults to `.derivedData/11x-signed`.

---

## Lane 3 — Notarized Developer ID release build

**Purpose:** Produce a public Gatekeeper-approved distributable app bundle and
zip. This is the authoritative release lane for 11x.

**When to use:**
- Shipping a public release.
- Producing a zip that can be downloaded and opened by users without Gatekeeper
  blocking.

**When not to use:**
- Do not use for fast compile checks (use Lane 1).
- Do not use for local ad-hoc testing if notarization credentials are not set up
  (use Lane 2).

**Requirements:**
- Developer ID Application certificate installed.
- Notary tool keychain profile `11x-notary` configured.
- Internet access for timestamping and notarization.

**Setup notary credentials (one-time):**

```bash
./scripts/release/store-notary-credentials.sh
```

**Command:**

```bash
./scripts/release/build-notarized-11x.sh
```

**Expected output:**
- `.derivedData/11x-signed/Build/Products/Release/11x.app`
- `.derivedData/11x-signed/Build/Products/Release/11x.zip`
- `codesign --verify --deep --strict` passes.
- `spctl -a -vvv -t execute` reports:
  - `source=Notarized Developer ID`
  - `origin=Developer ID Application: Kasey Upton (S58MT4ATKM)`
- Notarization ticket stapled (`xcrun stapler staple`).

**Environment overrides:**
- `DEVELOPMENT_TEAM` — defaults to `S58MT4ATKM`.
- `CODE_SIGN_IDENTITY` — defaults to `Developer ID Application: Kasey Upton (S58MT4ATKM)`.
- `NOTARY_PROFILE` — defaults to `11x-notary`.
- `DERIVED_DATA` — defaults to `.derivedData/11x-signed`.

**Known successful final release behavior:**
- Release build produced `11x.app`.
- Bundle ID: `app.kasey.11x`.
- URL scheme: `elevenx`.
- Hardened runtime enabled.
- `get-task-allow` absent.
- Sparkle nested helpers signed.
- Bundled `xcodegen` signed.
- Outer app re-signed last.
- Zip submitted to `notarytool`.
- Notarization accepted.
- Ticket stapled.
- `spctl` accepted with `source=Notarized Developer ID`.

---

## Quick comparison

| Lane | Config | Signing | Hardened runtime | Notarization | Use case |
|------|--------|---------|------------------|--------------|----------|
| 1 — verify-unsigned | Debug | None | No | No | Fast compile check |
| 2 — build-signed-release | Release | Developer ID | Yes | No | Local Release test / pre-notarization input |
| 3 — build-notarized-11x | Release | Developer ID | Yes | Yes + stapled | Public release |

---

## Common mistakes to avoid

1. **Do not run `codesign --verify` or `spctl` on a Lane 1 build.** The unsigned
   app is expected to fail both.
2. **Do not distribute a Lane 2 build.** It is signed but unnotarized; Gatekeeper
   will reject it on most Macs.
3. **Do not use Lane 3 for routine compile checks.** It requires credentials,
   internet, and Apple notarization latency.
4. **Do not change `APP_NAME`, `BUNDLE_ID`, or `URL_SCHEME` in these scripts**
   without updating `AppIdentity.swift`, `AppInfo.plist`, and tests.
5. **Do not confuse the historical `scripts/release/build-release.sh` and
   `verify-release.sh` with the 11x lanes.** Those scripts still assume the
   original 10x app name/bundle/feed and are not the 11x release path. The
   authoritative 11x release lane is `scripts/release/build-notarized-11x.sh`.

---

## Verification commands

After any build, check identity:

```bash
plutil -p .derivedData/<lane>/Build/Products/<config>/11x.app/Contents/Info.plist
```

After a signed build, check signature:

```bash
codesign -dv --verbose=4 .derivedData/11x-signed/Build/Products/Release/11x.app
```

After a signed build, check Gatekeeper:

```bash
spctl -a -vvv -t execute .derivedData/11x-signed/Build/Products/Release/11x.app
```

Run the forbidden runtime audit before any release:

```bash
./scripts/forbidden-audit
```

Run the full local test matrix:

```bash
xcrun swift test
```
