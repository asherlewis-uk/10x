#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd curl
require_cmd node
require_cmd plutil

app_path="${1:-/Applications/10x.app}"
info_plist="$app_path/Contents/Info.plist"

[[ -d "$app_path" ]] || fail "app bundle not found at $app_path"
[[ -f "$info_plist" ]] || fail "missing Info.plist at $info_plist"

plist_value() {
  local key="$1"
  plutil -extract "$key" raw -o - "$info_plist" 2>/dev/null || true
}

app_version="$(plist_value CFBundleShortVersionString)"
bundle_version="$(plist_value CFBundleVersion)"
bundle_identifier="$(plist_value CFBundleIdentifier)"
default_channel="$(plist_value DEFAULT_UPDATE_CHANNEL)"
feed_url="$(plist_value SUFeedURL)"

preferred_channel=""
if [[ -n "$bundle_identifier" ]]; then
  preferred_channel="$(defaults read "$bundle_identifier" preferredUpdateChannel 2>/dev/null || true)"
fi
if [[ -z "$preferred_channel" ]]; then
  preferred_channel="<build default>"
fi

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

stable_latest_path="$temp_dir/stable-latest.json"
beta_latest_path="$temp_dir/beta-latest.json"

curl -fsSL "$DIST_BASE_URL/stable/latest.json" -o "$stable_latest_path"
curl -fsSL "$DIST_BASE_URL/beta/latest.json" -o "$beta_latest_path"

echo "Installed app"
echo "  Path: $app_path"
echo "  Bundle ID: $bundle_identifier"
echo "  Version: $app_version"
echo "  Bundle version: $bundle_version"
echo "  Default channel: ${default_channel:-<missing>}"
echo "  Preferred channel: $preferred_channel"
echo "  Feed URL: ${feed_url:-<missing>}"
echo
echo "Live feeds"
echo "  Stable latest: $DIST_BASE_URL/stable/latest.json"
echo "  Beta latest: $DIST_BASE_URL/beta/latest.json"
echo

node -e '
  const fs = require("fs");

  const installedBundleVersion = Number.parseInt(process.argv[1], 10);
  const preferredChannel = process.argv[2];
  const stableLatest = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
  const betaLatest = JSON.parse(fs.readFileSync(process.argv[4], "utf8"));

  function describeRelease(label, latest) {
    return `${label}: ${latest.version} (build ${latest.build}, bundle ${latest.bundleVersion})`;
  }

  function compareInstalled(target) {
    const targetBundleVersion = Number.parseInt(target.bundleVersion, 10);
    if (!Number.isFinite(installedBundleVersion) || !Number.isFinite(targetBundleVersion)) {
      return "unknown";
    }
    if (installedBundleVersion < targetBundleVersion) {
      return "newer remote build available";
    }
    if (installedBundleVersion > targetBundleVersion) {
      return "installed build is newer";
    }
    return "same build";
  }

  console.log(`  ${describeRelease("Stable", stableLatest)} -> ${compareInstalled(stableLatest)}`);
  console.log(`  ${describeRelease("Beta", betaLatest)} -> ${compareInstalled(betaLatest)}`);
  console.log();

  const installedIsNewerThanBeta =
    Number.isFinite(installedBundleVersion) &&
    installedBundleVersion > Number.parseInt(betaLatest.bundleVersion, 10);

  if (preferredChannel === "beta" && installedIsNewerThanBeta) {
    console.log("Diagnosis");
    console.log("  Beta is selected, but the installed build is numerically newer than the current beta.");
    console.log("  Sparkle will not downgrade from that stable build onto the beta feed.");
    console.log("  Publish the next beta under a higher semver, such as 1.0.1-beta.1.");
    process.exit(0);
  }

  if (preferredChannel !== "beta" && Number.parseInt(stableLatest.bundleVersion, 10) > installedBundleVersion) {
    console.log("Diagnosis");
    console.log("  A newer stable build is available and should be visible to Sparkle.");
    process.exit(0);
  }

  if (preferredChannel === "beta" && Number.parseInt(betaLatest.bundleVersion, 10) > installedBundleVersion) {
    console.log("Diagnosis");
    console.log("  A newer beta build is available and should be visible to Sparkle.");
    process.exit(0);
  }

  console.log("Diagnosis");
  console.log("  No newer build is visible for the currently selected channel with the current version ordering.");
  console.log("  If you expected a same-version stable-to-beta move, Sparkle will treat that as a downgrade.");
  ' "$bundle_version" "$preferred_channel" "$stable_latest_path" "$beta_latest_path"
