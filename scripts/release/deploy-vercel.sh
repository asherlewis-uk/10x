#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd npx
require_env VERCEL_TOKEN
require_env VERCEL_PROJECT_ID
require_env VERCEL_ORG_ID

VERCEL_TOKEN="$(printf '%s' "$VERCEL_TOKEN" | tr -d '\r\n')"
VERCEL_PROJECT_ID="$(printf '%s' "$VERCEL_PROJECT_ID" | tr -d '\r\n')"
VERCEL_ORG_ID="$(printf '%s' "$VERCEL_ORG_ID" | tr -d '\r\n')"
if [[ -n "${VERCEL_SCOPE:-}" ]]; then
  VERCEL_SCOPE="$(printf '%s' "$VERCEL_SCOPE" | tr -d '\r\n')"
fi

site_root="${1:-}"
[[ -n "$site_root" ]] || fail "missing site root. Usage: $0 <site-root>"
[[ -d "$site_root" ]] || fail "site root does not exist: $site_root"

mkdir -p "$site_root/.vercel"
cat > "$site_root/.vercel/project.json" <<EOF
{
  "orgId": "${VERCEL_ORG_ID}",
  "projectId": "${VERCEL_PROJECT_ID}"
}
EOF

log "Deploying static beta site to Vercel"
if [[ -n "${VERCEL_SCOPE:-}" ]]; then
  npx --yes vercel@latest deploy \
    --prod \
    --yes \
    --token "$VERCEL_TOKEN" \
    --cwd "$site_root" \
    --scope "$VERCEL_SCOPE"
else
  npx --yes vercel@latest deploy \
    --prod \
    --yes \
    --token "$VERCEL_TOKEN" \
    --cwd "$site_root"
fi
