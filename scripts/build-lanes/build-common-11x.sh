#!/usr/bin/env bash
set -euo pipefail

# Shared configuration for 11x macOS build lanes.
# Sourced by scripts in this directory; not meant to be run directly.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

# Locked 11x product identity. These must match AppIdentity.swift and AppInfo.plist.
export APP_NAME="11x"
export APP_BUNDLE_NAME="${APP_NAME}.app"
export BUNDLE_ID="app.kasey.11x"
export URL_SCHEME="elevenx"
export APP_SUPPORT_NAME="11x"

# Xcode project/scheme names are historical 10x-era build-system identifiers.
export PROJECT="10x-macos.xcodeproj"
export SCHEME="10x-macos"

# Default signing identity for 11x signed Release and notarized release lanes.
export TEAM_ID="${DEVELOPMENT_TEAM:-S58MT4ATKM}"
export IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application: Kasey Upton (S58MT4ATKM)}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[11x-build] error: required command not found: $1" >&2
    exit 1
  fi
}

require_identity() {
  require_cmd codesign
  if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    echo "[11x-build] error: signing identity not found in keychain: $IDENTITY" >&2
    echo "[11x-build]        Install the Developer ID Application certificate or set CODE_SIGN_IDENTITY." >&2
    exit 1
  fi
}

require_notary_profile() {
  local profile="${NOTARY_PROFILE:-11x-notary}"
  if ! xcrun notarytool submit --help >/dev/null 2>&1; then
    echo "[11x-build] error: notarytool is not available" >&2
    exit 1
  fi
  if [[ -z "$profile" ]]; then
    echo "[11x-build] error: NOTARY_PROFILE must be set" >&2
    exit 1
  fi
  echo "$profile"
}

verify_app_identity() {
  local app_path="$1"
  local plist_path="$app_path/Contents/Info.plist"

  require_cmd /usr/libexec/PlistBuddy

  local display_name bundle_name bundle_id url_schemes
  display_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist_path" 2>/dev/null)
  bundle_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist_path" 2>/dev/null)
  bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_path" 2>/dev/null)
  url_schemes=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" "$plist_path" 2>/dev/null || true)

  [[ "$display_name" == "$APP_NAME" ]] || {
    echo "[11x-build] error: CFBundleDisplayName is '$display_name', expected '$APP_NAME'" >&2
    return 1
  }
  [[ "$bundle_name" == "$APP_NAME" ]] || {
    echo "[11x-build] error: CFBundleName is '$bundle_name', expected '$APP_NAME'" >&2
    return 1
  }
  [[ "$bundle_id" == "$BUNDLE_ID" ]] || {
    echo "[11x-build] error: CFBundleIdentifier is '$bundle_id', expected '$BUNDLE_ID'" >&2
    return 1
  }
  [[ "$url_schemes" == *"$URL_SCHEME"* ]] || {
    echo "[11x-build] error: URL scheme '$URL_SCHEME' not found in CFBundleURLSchemes: $url_schemes" >&2
    return 1
  }

  return 0
}

verify_no_vendor_artifacts() {
  local app_path="$1"
  local matches
  matches=$(find "$app_path" -iname '*supabase*' -o -iname '*superwall*' 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    echo "[11x-build] error: vendor-named artifacts found inside built app:" >&2
    echo "$matches" >&2
    return 1
  fi
  return 0
}
