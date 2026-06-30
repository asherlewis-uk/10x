#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

APP_NAME="11x"
PROJECT="10x-macos.xcodeproj"
SCHEME="10x-macos"
CONFIGURATION="Release"
TEAM_ID="${DEVELOPMENT_TEAM:-S58MT4ATKM}"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: Kasey Upton (S58MT4ATKM)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-11x-notary}"
DERIVED_DATA="${DERIVED_DATA:-.derivedData/11x-signed}"

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
ZIP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.zip"

echo "==> Cleaning signed derived data"
rm -rf "$DERIVED_DATA"

echo "==> Building signed Release app"
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

echo "==> Signing nested Sparkle helpers and bundled xcodegen"
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

echo "==> Re-signing outer app last"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=4 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|Runtime|Identifier" || true

echo "==> Verifying app entitlements"
ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"

if echo "$ENTITLEMENTS" | grep -q "com.apple.security.get-task-allow"; then
  echo "ERROR: get-task-allow entitlement is present. Notarization will fail."
  exit 1
fi

echo "==> Creating notarization zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to Apple notarization"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper verification"
spctl -a -vvv -t execute "$APP"

echo
echo "DONE:"
echo "  App: $APP"
echo "  Zip: $ZIP"