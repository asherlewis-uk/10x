#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd security

cert_path="${1:-${DEV_ID_P12_PATH:-}}"
cert_password="${2:-${DEV_ID_P12_PASSWORD:-}}"
keychain_path="${3:-${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}}"

[[ -n "$cert_path" ]] || fail "missing Developer ID certificate path. Usage: $0 <p12-path> <p12-password> [keychain]"
[[ -f "$cert_path" ]] || fail "certificate file not found: $cert_path"
[[ -n "$cert_password" ]] || fail "missing Developer ID certificate password"

security import "$cert_path" \
  -k "$keychain_path" \
  -P "$cert_password" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "" \
  "$keychain_path" >/dev/null 2>&1 || true

identity=$(security find-identity -v -p codesigning "$keychain_path" | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[[ -n "$identity" ]] || fail "Developer ID Application identity was not found after import"

log "Imported Developer ID Application certificate:"
printf '%s\n' "$identity"

