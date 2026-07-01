#!/usr/bin/env bash
set -euo pipefail

# Lane 1 — Fast unsigned verification build.
# Purpose: CI/dev sanity. Fastest compile check. Does not produce a
# distributable app and must not be confused with signed/notarized release
# builds. Strict codesign/spctl checks are intentionally skipped because an
# unsigned app is expected to fail them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./build-common-11x.sh
source "$SCRIPT_DIR/build-common-11x.sh"

require_cmd xcodebuild
require_cmd plutil
require_cmd find

DERIVED_DATA="${DERIVED_DATA:-.derivedData/10x-macos}"
CONFIGURATION="Debug"
APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_BUNDLE_NAME"

echo "[11x-build] Lane 1: fast unsigned verification build"
echo "[11x-build] DerivedData: $DERIVED_DATA"

echo "[11x-build] Cleaning previous unsigned derived data"
rm -rf "$DERIVED_DATA"

echo "[11x-build] Building $APP_NAME.app with signing disabled"
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build \
  CODE_SIGNING_ALLOWED=NO

echo "[11x-build] Verifying built app identity"
verify_app_identity "$APP"

echo "[11x-build] Verifying no Supabase/Superwall artifacts in bundle"
verify_no_vendor_artifacts "$APP"

echo "[11x-build] Lane 1 complete: $APP"
echo "[11x-build] NOTE: codesign/spctl checks are expected to fail on unsigned builds."
