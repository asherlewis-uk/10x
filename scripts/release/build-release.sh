#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd xcodebuild
require_cmd ditto
require_cmd codesign
require_cmd file

resolve_version_build "${1:-}" "${2:-}" "${3:-}"
reset_release_dir

build_signed=false

if signed_build_requested; then
  build_signed=true
  require_env APPLE_TEAM_ID
  require_env DEV_ID_APP_CERT_NAME
  build_codesign_keychain_args

  export_options_path="$RELEASE_DIR/ExportOptions.plist"
  export_signing_style="automatic"
  provisioning_block=""
  archive_signing_args=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$DEV_ID_APP_CERT_NAME"
  )
  release_entitlements_path="$REPO_ROOT/10x-macos/10x_macos_release.entitlements"
  release_requires_provisioning_profile=false

  if [[ -f "$release_entitlements_path" ]] && \
    grep -Eq '<key>com\.apple\.developer\.|<key>keychain-access-groups</key>' "$release_entitlements_path"; then
    release_requires_provisioning_profile=true
  fi

  if [[ -n "${DEV_ID_PROFILE_NAME:-}" && "$release_requires_provisioning_profile" == true ]]; then
    export_signing_style="manual"
    provisioning_block=$(cat <<EOF
    <key>provisioningProfiles</key>
    <dict>
        <key>app.10x.macos</key>
        <string>${DEV_ID_PROFILE_NAME}</string>
    </dict>
EOF
)
  elif [[ -n "${DEV_ID_PROFILE_NAME:-}" ]]; then
    log "Developer ID provisioning profile is installed but current release entitlements do not require it; using automatic signing."
  fi

  python3 - <<'PY' "$SCRIPT_DIR/ExportOptions.plist.template" "$export_options_path" "$APPLE_TEAM_ID" "$export_signing_style" "$provisioning_block"
from pathlib import Path
import sys

template_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
team_id = sys.argv[3]
signing_style = sys.argv[4]
provisioning_block = sys.argv[5]

content = template_path.read_text()
content = content.replace("__TEAM_ID__", team_id)
content = content.replace("__SIGNING_STYLE__", signing_style)
content = content.replace("__PROVISIONING_BLOCK__", provisioning_block)
output_path.write_text(content)
PY

  log "Archiving signed release for ${APP_NAME} ${APP_VERSION} (${APP_BUILD})"
  archive_cmd=(
    xcodebuild archive
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration Release
    -destination "generic/platform=macOS"
    -archivePath "$ARCHIVE_PATH"
    MARKETING_VERSION="$APP_VERSION"
    CURRENT_PROJECT_VERSION="$INTERNAL_BUNDLE_VERSION"
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
    DEFAULT_UPDATE_CHANNEL="$RELEASE_CHANNEL"
    SPARKLE_FEED_URL="$CANONICAL_SPARKLE_FEED_URL"
  )
  if (( ${#archive_signing_args[@]} > 0 )); then
    archive_cmd+=("${archive_signing_args[@]}")
  fi
  "${archive_cmd[@]}"

  export_log_path="$RELEASE_DIR/export.log"
  export_succeeded=false
  for attempt in 1 2 3; do
    log "Exporting Developer ID app bundle (attempt ${attempt}/3)"
    export_cmd=(
      xcodebuild -exportArchive
      -archivePath "$ARCHIVE_PATH"
      -exportOptionsPlist "$export_options_path"
      -exportPath "$EXPORT_DIR"
    )
    if "${export_cmd[@]}" 2>&1 | tee "$export_log_path"; then
      export_succeeded=true
      break
    fi

    if grep -q "The timestamp service is not available" "$export_log_path" && (( attempt < 3 )); then
      log "Apple timestamp service unavailable during export; retrying in 20 seconds"
      sleep 20
      rm -rf "$EXPORT_DIR"
      mkdir -p "$EXPORT_DIR"
      continue
    fi

    break
  done

  [[ "$export_succeeded" == true ]] || fail "Developer ID export failed. See $export_log_path"

  resource_dir="$EXPORT_APP_PATH/Contents/Resources"
  resigned_nested_code=false
  if [[ -d "$resource_dir" ]]; then
    while IFS= read -r resource_path; do
      [[ -n "$resource_path" ]] || continue
      if file -b "$resource_path" | grep -q "Mach-O"; then
        log "Signing bundled executable resource $(basename "$resource_path") with hardened runtime"
        codesign \
          --force \
          --sign "$DEV_ID_APP_CERT_NAME" \
          --timestamp \
          --options runtime \
          "${CODESIGN_KEYCHAIN_ARGS[@]}" \
          "$resource_path"
        resigned_nested_code=true
      fi
    done < <(find "$resource_dir" -type f -perm -111)
  fi

  if [[ "$resigned_nested_code" == true ]]; then
    entitlements_path="$RELEASE_DIR/exported-app-entitlements.plist"
    codesign -d --entitlements :- "$EXPORT_APP_PATH" > "$entitlements_path" 2>/dev/null

    log "Re-signing app bundle after nested executable updates"
    codesign \
      --force \
      --sign "$DEV_ID_APP_CERT_NAME" \
      --timestamp \
      --options runtime \
      --entitlements "$entitlements_path" \
      "${CODESIGN_KEYCHAIN_ARGS[@]}" \
      "$EXPORT_APP_PATH"
  fi
else
  log "Developer ID credentials not set; building unsigned release bundle"
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$APP_VERSION" \
    CURRENT_PROJECT_VERSION="$INTERNAL_BUNDLE_VERSION" \
    DEFAULT_UPDATE_CHANNEL="$RELEASE_CHANNEL" \
    SPARKLE_FEED_URL="$CANONICAL_SPARKLE_FEED_URL" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

  ditto "$ARCHIVE_APP_PATH" "$EXPORT_APP_PATH"
fi

app_path="$(release_app_path)"

cat > "$BUILD_METADATA_PATH" <<EOF
{
  "channel": "${RELEASE_CHANNEL}",
  "version": "${APP_VERSION}",
  "build": "${APP_BUILD}",
  "bundleVersion": "${INTERNAL_BUNDLE_VERSION}",
  "signed": ${build_signed},
  "appPath": "${app_path}",
  "archivePath": "${ARCHIVE_PATH}"
}
EOF

log "Release app bundle ready at $app_path"
