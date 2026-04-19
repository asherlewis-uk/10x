#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd hdiutil
require_cmd ditto
require_cmd osascript
require_cmd xcrun
require_cmd DeRez
require_cmd Rez
require_cmd SetFile
require_cmd sips

resolve_version_build "${1:-}" "${2:-}" "${3:-}"
ensure_release_dir

app_path="$(release_app_path)"
staging_dir="$RELEASE_DIR/dmg-root"
background_dir="$staging_dir/.background"
background_name="install-background.png"
background_path="$background_dir/$background_name"
temp_dmg="$RELEASE_DIR/${ARTIFACT_BASENAME}-rw.dmg"
volume_name="${DMG_VOLUME_NAME:-$DMG_VOLUME_NAME_DEFAULT}"
mount_dir="/Volumes/$volume_name"
window_left=200
window_top=120
window_width=560
window_height=340
app_icon_x=160
app_icon_y=150
applications_icon_x=400
applications_icon_y=150

render_toolbar_icon() {
  local output_path="$1"
  local size="$2"

  xcrun swift \
    "$SCRIPT_DIR/render-dmg-app-icon.swift" \
    "$output_path" \
    "$size"
}

apply_install_icon() {
  local bundle_path="$1"
  local temp_dir
  local icon_png
  local resource_file
  local custom_icon_file

  temp_dir=$(mktemp -d)
  icon_png="$temp_dir/10x-mark.png"
  resource_file="$temp_dir/10x-mark.rsrc"
  custom_icon_file="$bundle_path/Icon"$'\r'

  render_toolbar_icon "$icon_png" 1024
  sips -i "$icon_png" >/dev/null
  rm -f "$custom_icon_file"
  DeRez -only icns "$icon_png" >"$resource_file"
  Rez -append "$resource_file" -o "$custom_icon_file"
  SetFile -a C "$bundle_path"
  SetFile -a V "$custom_icon_file"
  touch "$bundle_path"

  rm -rf "$temp_dir"
}

cleanup() {
  local exit_code=$?
  trap - EXIT

  if mount | grep -Fq "on $mount_dir "; then
    hdiutil detach "$mount_dir" -quiet || true
  fi

  if [[ -d "$mount_dir" ]] && ! mount | grep -Fq "on $mount_dir "; then
    rmdir "$mount_dir" 2>/dev/null || true
  fi
  exit "$exit_code"
}

trap cleanup EXIT

rm -rf "$staging_dir" "$DMG_PATH" "$temp_dmg"
mkdir -p "$background_dir"

ditto "$app_path" "$staging_dir/$APP_BUNDLE_NAME"
apply_install_icon "$staging_dir/$APP_BUNDLE_NAME"
ln -s /Applications "$staging_dir/Applications"
chflags hidden "$background_dir" || true

xcrun swift \
  "$SCRIPT_DIR/render-dmg-background.swift" \
  "$background_path" \
  "$window_width" \
  "$window_height"

log "Creating writable DMG template"
hdiutil create \
  -volname "$volume_name" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$temp_dmg"

if mount | grep -Fq "on $mount_dir "; then
  hdiutil detach "$mount_dir" -quiet || true
  sleep 1
fi

if [[ -d "$mount_dir" ]]; then
  rmdir "$mount_dir" 2>/dev/null || true
fi

hdiutil attach \
  "$temp_dmg" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$mount_dir" \
  >/dev/null

chflags hidden "$mount_dir/.background" || true

log "Configuring Finder window layout"
osascript <<EOF
tell application "Finder"
  set dmgDisk to disk of (POSIX file "$mount_dir" as alias)
  tell dmgDisk
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$window_left, $window_top, $(($window_left + $window_width)), $(($window_top + $window_height))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 14
    set background picture of viewOptions to (POSIX file "$mount_dir/.background/$background_name" as alias)
    set position of item "$APP_BUNDLE_NAME" of container window to {$app_icon_x, $app_icon_y}
    set position of item "Applications" of container window to {$applications_icon_x, $applications_icon_y}
    close
    open
    update without registering applications
    delay 2
    close
    delay 1
  end tell
end tell
EOF

sync
sleep 1

hdiutil detach "$mount_dir" >/dev/null
rmdir "$mount_dir" 2>/dev/null || true

log "Converting DMG to final artifact at $DMG_PATH"
hdiutil convert \
  "$temp_dmg" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" \
  >/dev/null

rm -f "$temp_dmg"

log "DMG ready at $DMG_PATH"
