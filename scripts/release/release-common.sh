#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

APP_NAME="10x"
APP_BUNDLE_NAME="${APP_NAME}.app"
APP_SLUG="10x"
SCHEME="10x-macos"
PROJECT_PATH="$REPO_ROOT/10x-macos.xcodeproj"
BUILD_ROOT="$REPO_ROOT/build/release"
RELEASE_NOTES_REPO_DIR="$REPO_ROOT/scripts/release/release-notes"
DEFAULT_DOWNLOADS_ROOT="$BUILD_ROOT/published-site"
DIST_BASE_URL="${DIST_BASE_URL:-https://downloads.example.invalid}"
CANONICAL_SPARKLE_FEED_URL="${CANONICAL_SPARKLE_FEED_URL:-$DIST_BASE_URL/appcast.xml}"
SPARKLE_KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-10x-app-builder}"
STABLE_BUILD_NUMBER=9000
BETA_MAX_BUILD_NUMBER=8999

log() {
  printf '[release] %s\n' "$*"
}

fail() {
  printf '[release] error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "missing required environment variable: $name"
}

signed_build_requested() {
  [[ -n "${APPLE_TEAM_ID:-}" && -n "${DEV_ID_APP_CERT_NAME:-}" ]]
}

compute_internal_bundle_version() {
  local major minor patch
  IFS=. read -r major minor patch <<<"$APP_VERSION"

  [[ "$major" =~ ^[0-9]+$ ]] || fail "version major component must be numeric: $APP_VERSION"
  [[ "$minor" =~ ^[0-9]+$ ]] || fail "version minor component must be numeric: $APP_VERSION"
  [[ "$patch" =~ ^[0-9]+$ ]] || fail "version patch component must be numeric: $APP_VERSION"
  [[ "$APP_BUILD" =~ ^[0-9]+$ ]] || fail "build number must be numeric: $APP_BUILD"

  INTERNAL_BUNDLE_VERSION=$(printf '%d%03d%03d%04d' "$major" "$minor" "$patch" "$APP_BUILD")
  export INTERNAL_BUNDLE_VERSION
}

validate_release_channel() {
  case "$1" in
    stable|beta) ;;
    *) fail "unsupported release channel '$1'. Expected 'stable' or 'beta'" ;;
  esac
}

resolve_version_build() {
  local version="${1:-${APP_VERSION:-}}"
  local build="${2:-${APP_BUILD:-}}"
  local channel="${3:-${RELEASE_CHANNEL:-beta}}"

  validate_release_channel "$channel"

  [[ -n "$version" ]] || fail "missing version. Usage: $0 <version> <build> [channel]"
  [[ -n "$build" ]] || fail "missing build number. Usage: $0 <version> <build> [channel]"

  if [[ "$channel" == "stable" ]]; then
    [[ "$build" == "$STABLE_BUILD_NUMBER" ]] || fail "stable releases must use build $STABLE_BUILD_NUMBER"
  else
    [[ "$build" =~ ^[0-9]+$ ]] || fail "build number must be numeric: $build"
    (( build >= 1 && build <= BETA_MAX_BUILD_NUMBER )) || fail "beta builds must be between 1 and $BETA_MAX_BUILD_NUMBER"
  fi

  export APP_VERSION="$version"
  export APP_BUILD="$build"
  export RELEASE_CHANNEL="$channel"
  compute_internal_bundle_version

  if [[ "$RELEASE_CHANNEL" == "stable" ]]; then
    RELEASE_CHANNEL_TITLE="Stable"
    RELEASE_CHANNEL_DESCRIPTION="stable"
    RELEASE_NOTES_SLUG="$APP_VERSION"
    ARTIFACT_BASENAME="${APP_SLUG}-${APP_VERSION}"
    DMG_VOLUME_NAME_DEFAULT="$APP_NAME"
  else
    RELEASE_CHANNEL_TITLE="Beta"
    RELEASE_CHANNEL_DESCRIPTION="beta"
    RELEASE_NOTES_SLUG="${APP_VERSION}-beta.${APP_BUILD}"
    ARTIFACT_BASENAME="${APP_SLUG}-${APP_VERSION}-beta.${APP_BUILD}"
    DMG_VOLUME_NAME_DEFAULT="${APP_NAME} Beta"
  fi

  RELEASE_DIR="$BUILD_ROOT/$RELEASE_CHANNEL/$RELEASE_NOTES_SLUG"
  ARCHIVE_PATH="$RELEASE_DIR/${APP_SLUG}.xcarchive"
  EXPORT_DIR="$RELEASE_DIR/export"
  EXPORT_APP_PATH="$EXPORT_DIR/$APP_BUNDLE_NAME"
  ARCHIVE_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_BUNDLE_NAME"
  DMG_PATH="$RELEASE_DIR/${ARTIFACT_BASENAME}.dmg"
  RELEASE_NOTES_PATH_DEFAULT="$RELEASE_DIR/release-notes.html"
  RELEASE_NOTES_PATH_REPO_BUILD_DEFAULT="$RELEASE_NOTES_REPO_DIR/$RELEASE_NOTES_SLUG.html"
  RELEASE_NOTES_PATH_REPO_DEFAULT="$RELEASE_NOTES_REPO_DIR/$APP_VERSION.html"
  BUILD_METADATA_PATH="$RELEASE_DIR/build-metadata.json"
  RELEASE_CHANNEL_BASE_URL="$DIST_BASE_URL/$RELEASE_CHANNEL"
  RELEASE_CHANNEL_APPCAST_URL="$RELEASE_CHANNEL_BASE_URL/appcast.xml"

  export RELEASE_DIR ARCHIVE_PATH EXPORT_DIR EXPORT_APP_PATH ARCHIVE_APP_PATH
  export ARTIFACT_BASENAME DMG_PATH RELEASE_NOTES_PATH_DEFAULT BUILD_METADATA_PATH
  export RELEASE_NOTES_SLUG RELEASE_NOTES_PATH_REPO_BUILD_DEFAULT RELEASE_NOTES_PATH_REPO_DEFAULT
  export RELEASE_CHANNEL_TITLE RELEASE_CHANNEL_DESCRIPTION RELEASE_CHANNEL_BASE_URL RELEASE_CHANNEL_APPCAST_URL
  export DMG_VOLUME_NAME_DEFAULT SPARKLE_KEYCHAIN_ACCOUNT CANONICAL_SPARKLE_FEED_URL
}

reset_release_dir() {
  rm -rf "$RELEASE_DIR"
  mkdir -p "$EXPORT_DIR"
}

ensure_release_dir() {
  mkdir -p "$EXPORT_DIR"
}

release_app_path() {
  if [[ -d "$EXPORT_APP_PATH" ]]; then
    printf '%s\n' "$EXPORT_APP_PATH"
  elif [[ -d "$ARCHIVE_APP_PATH" ]]; then
    printf '%s\n' "$ARCHIVE_APP_PATH"
  else
    fail "release app bundle not found in $EXPORT_DIR or $ARCHIVE_PATH"
  fi
}

build_codesign_keychain_args() {
  CODESIGN_KEYCHAIN_ARGS=()
  if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    CODESIGN_KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN")
  fi
}

build_notary_keychain_args() {
  NOTARY_KEYCHAIN_ARGS=()
  if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    NOTARY_KEYCHAIN_ARGS=(--keychain "$NOTARY_KEYCHAIN")
  fi
}

maybe_find_sparkle_bin_dir() {
  if [[ -n "${SPARKLE_BIN_DIR:-}" && -d "${SPARKLE_BIN_DIR:-}" ]]; then
    printf '%s\n' "$SPARKLE_BIN_DIR"
    return 0
  fi

  local candidate
  while IFS= read -r candidate; do
    printf '%s\n' "$candidate"
    return 0
  done < <(
    find \
      "$HOME/Library/Developer/Xcode/DerivedData" \
      "$REPO_ROOT/.build" \
      -type d \
      \( -path '*/SourcePackages/artifacts/*/Sparkle/bin' -o -path '*/artifacts/*/Sparkle/bin' \) \
      2>/dev/null | sort
  )

  return 1
}

sparkle_tool_path() {
  local bin_dir
  bin_dir="$(maybe_find_sparkle_bin_dir)" || fail "could not locate Sparkle tools; set SPARKLE_BIN_DIR"
  [[ -x "$bin_dir/$1" ]] || fail "missing Sparkle tool: $bin_dir/$1"
  printf '%s\n' "$bin_dir/$1"
}
