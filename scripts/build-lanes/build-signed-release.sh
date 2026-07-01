#!/usr/bin/env bash
set -euo pipefail

# Lane 2 — Signed local Release build.
# Purpose: produce a hardened-runtime-signed Release app for local testing,
# ad-hoc distribution, or as the input to a separate notarization step. This
# lane does not submit to Apple notarization. It does not produce a public
# distributable package on its own.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./build-common-11x.sh
source "$SCRIPT_DIR/build-common-11x.sh"

require_cmd xcodebuild
require_cmd codesign
require_cmd /usr/libexec/PlistBuddy
require_cmd find

require_identity

DERIVED_DATA="${DERIVED_DATA:-.derivedData/11x-signed}"
CONFIGURATION="Release"
APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_BUNDLE_NAME"

echo "[11x-build] Lane 2: signed local Release build"
echo "[11x-build] Identity: $IDENTITY"
echo "[11x-build] DerivedData: $DERIVED_DATA"

echo "[11x-build] Cleaning previous signed derived data"
rm -rf "$DERIVED_DATA"

echo "[11x-build] Building signed Release app"
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

echo "[11x-build] Signing nested Sparkle helpers and bundled xcodegen"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework"

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Resources/xcodegen"

echo "[11x-build] Re-signing outer app last"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "[11x-build] Verifying signature"
codesign --verify --deep --strict --verbose=4 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|Runtime|Identifier" || true

echo "[11x-build] Verifying entitlements"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"

if echo "$ENTITLEMENTS" | grep -q "com.apple.security.get-task-allow"; then
  echo "[11x-build] error: get-task-allow entitlement is present. Notarization would fail." >&2
  exit 1
fi

echo "[11x-build] Verifying built app identity"
verify_app_identity "$APP"

echo "[11x-build] Verifying no Supabase/Superwall artifacts in bundle"
verify_no_vendor_artifacts "$APP"

echo "[11x-build] Gatekeeper status (expected: rejected because not notarized)"
spctl -a -vvv -t execute "$APP" || true

echo "[11x-build] Lane 2 complete: $APP"
echo "[11x-build] NOTE: This app is signed but not notarized. Gatekeeper may still block it on other Macs."
echo "[11x-build]       For a public release, run Lane 3: scripts/release/build-notarized-11x.sh"
