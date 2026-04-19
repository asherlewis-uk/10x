#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd codesign
require_cmd xcrun

resolve_version_build "${1:-}" "${2:-}" "${3:-}"
ensure_release_dir

require_env DEV_ID_APP_CERT_NAME

[[ -f "$DMG_PATH" ]] || fail "DMG not found at $DMG_PATH. Run create-dmg.sh first."

build_codesign_keychain_args

log "Signing DMG with Developer ID identity"
codesign --force --sign "$DEV_ID_APP_CERT_NAME" "${CODESIGN_KEYCHAIN_ARGS[@]}" "$DMG_PATH"

log "Submitting DMG to Apple notarization service"
notary_submit_args=()
if [[ -n "${NOTARY_API_KEY_PATH:-}" ]]; then
  require_env NOTARY_KEY_ID
  require_env NOTARY_ISSUER_ID
  [[ -f "$NOTARY_API_KEY_PATH" ]] || fail "notary API key file not found: $NOTARY_API_KEY_PATH"
  notary_submit_args=(
    --key "$NOTARY_API_KEY_PATH"
    --key-id "$NOTARY_KEY_ID"
    --issuer "$NOTARY_ISSUER_ID"
  )
else
  require_env NOTARY_KEYCHAIN_PROFILE
  build_notary_keychain_args
  notary_submit_args=(
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE"
    "${NOTARY_KEYCHAIN_ARGS[@]}"
  )
fi

notary_submit_log="$RELEASE_DIR/notary-submit.json"
notary_detail_log="$RELEASE_DIR/notary-log.json"

xcrun notarytool submit \
  "$DMG_PATH" \
  "${notary_submit_args[@]}" \
  --wait \
  --output-format json > "$notary_submit_log"

submission_id=$(python3 - <<'PY' "$notary_submit_log"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("id", ""))
PY
)

submission_status=$(python3 - <<'PY' "$notary_submit_log"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get("status", ""))
PY
)

if [[ "$submission_status" != "Accepted" ]]; then
  if [[ -n "$submission_id" ]]; then
    log "Fetching notarization detail log for failed submission $submission_id"
    xcrun notarytool log \
      "$submission_id" \
      "${notary_submit_args[@]}" > "$notary_detail_log" || true
    [[ -f "$notary_detail_log" ]] && cat "$notary_detail_log" >&2
  fi
  fail "notarization failed with status '$submission_status'"
fi

log "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

log "Notarized DMG ready at $DMG_PATH"
