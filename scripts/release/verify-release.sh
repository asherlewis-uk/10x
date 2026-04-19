#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd /usr/libexec/PlistBuddy
require_cmd codesign
require_cmd spctl
require_cmd xcrun

resolve_version_build "${1:-}" "${2:-}" "${3:-}"
ensure_release_dir

app_path="$(release_app_path)"
plist_path="$app_path/Contents/Info.plist"

[[ -f "$plist_path" ]] || fail "missing app Info.plist at $plist_path"
[[ "$(basename "$app_path")" == "$APP_BUNDLE_NAME" ]] || fail "unexpected app bundle name at $app_path"

display_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist_path")
bundle_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist_path")
bundle_identifier=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_path")
minimum_system_version=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$plist_path")
bundle_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist_path")
short_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist_path")
sparkle_feed_url=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$plist_path")
default_update_channel=$(/usr/libexec/PlistBuddy -c "Print :DEFAULT_UPDATE_CHANNEL" "$plist_path")

[[ "$display_name" == "$APP_NAME" ]] || fail "CFBundleDisplayName is '$display_name', expected '$APP_NAME'"
[[ "$bundle_name" == "$APP_NAME" ]] || fail "CFBundleName is '$bundle_name', expected '$APP_NAME'"
[[ "$bundle_identifier" == "app.10x.macos" ]] || fail "CFBundleIdentifier is '$bundle_identifier', expected 'app.10x.macos'"
[[ "$minimum_system_version" == "14.0" ]] || fail "LSMinimumSystemVersion is '$minimum_system_version', expected '14.0'"
[[ "$bundle_version" == "$INTERNAL_BUNDLE_VERSION" ]] || fail "CFBundleVersion is '$bundle_version', expected '$INTERNAL_BUNDLE_VERSION'"
[[ "$short_version" == "$APP_VERSION" ]] || fail "CFBundleShortVersionString is '$short_version', expected '$APP_VERSION'"
[[ "$sparkle_feed_url" == "$CANONICAL_SPARKLE_FEED_URL" ]] || fail "SUFeedURL is '$sparkle_feed_url', expected '$CANONICAL_SPARKLE_FEED_URL'"
[[ "$default_update_channel" == "$RELEASE_CHANNEL" ]] || fail "DEFAULT_UPDATE_CHANNEL is '$default_update_channel', expected '$RELEASE_CHANNEL'"

if signed_build_requested; then
  log "Verifying signed app bundle"
  codesign --verify --deep --strict --verbose=2 "$app_path"
  spctl -a -vv --type execute "$app_path"
else
  log "App bundle is unsigned by design for this prep build; skipped codesign and Gatekeeper execution checks."
fi

if [[ -f "$DMG_PATH" ]]; then
  if signed_build_requested; then
    log "Verifying signed DMG"
    codesign --verify --verbose=2 "$DMG_PATH"
    spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
  else
    log "DMG is unsigned by design for this prep build; skipped DMG signature and Gatekeeper checks."
  fi

  if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    log "Stapled notarization ticket is present on the DMG."
  else
    log "DMG does not have a stapled notarization ticket yet."
  fi
fi

log "Release metadata checks passed for ${APP_NAME} ${APP_VERSION} (${APP_BUILD})"
