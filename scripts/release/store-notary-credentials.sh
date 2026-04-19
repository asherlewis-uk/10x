#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd xcrun

profile_name="${NOTARY_KEYCHAIN_PROFILE:-tenx-notary}"
key_path="${1:-${APPLE_NOTARY_KEY_PATH:-}}"
key_id="${2:-${APPLE_NOTARY_KEY_ID:-}}"
issuer_id="${3:-${APPLE_NOTARY_ISSUER_ID:-}}"
team_id="${4:-${APPLE_TEAM_ID:-}}"

[[ -n "$key_path" ]] || fail "missing App Store Connect API key path. Usage: $0 <p8-path> <key-id> <issuer-id> <team-id>"
[[ -f "$key_path" ]] || fail "API key file not found: $key_path"
[[ -n "$key_id" ]] || fail "missing App Store Connect key ID"
[[ -n "$issuer_id" ]] || fail "missing App Store Connect issuer ID"
[[ -n "$team_id" ]] || fail "missing Apple team ID"

build_notary_keychain_args

xcrun notarytool store-credentials "$profile_name" \
  --key "$key_path" \
  --key-id "$key_id" \
  --issuer "$issuer_id" \
  --team-id "$team_id" \
  "${NOTARY_KEYCHAIN_ARGS[@]}"

log "Stored notarytool credentials in profile '$profile_name'"
