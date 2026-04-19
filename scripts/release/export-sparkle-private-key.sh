#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd base64

account="${1:-${SPARKLE_KEYCHAIN_ACCOUNT:-10x-app-builder}}"
output_path="${2:-$REPO_ROOT/build/release/sparkle_private_key.txt}"

mkdir -p "$(dirname "$output_path")"

generate_keys=$(sparkle_tool_path generate_keys)
"$generate_keys" --account "$account" -x "$output_path"

log "Exported Sparkle private key for account '$account' to $output_path"
printf '\nAdd this file contents as the GitHub Actions secret SPARKLE_PRIVATE_KEY_BASE64.\n'
