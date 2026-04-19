#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./release-common.sh
source "$SCRIPT_DIR/release-common.sh"

require_cmd cp
require_cmd curl
require_cmd date
require_cmd find
require_cmd mkdir
require_cmd node
require_cmd rm
require_cmd shasum

resolve_version_build "${1:-}" "${2:-}" "${3:-}"
ensure_release_dir

downloads_root="${4:-${DOWNLOADS_ROOT:-$DEFAULT_DOWNLOADS_ROOT}}"
public_root="$downloads_root/public"
channel_root="$public_root/$RELEASE_CHANNEL"
downloads_dir="$channel_root/downloads"
release_notes_dir="$channel_root/release-notes"
release_notes_source="${RELEASE_NOTES_PATH:-}"
release_notes_target="$release_notes_dir/${RELEASE_NOTES_SLUG}.html"
dmg_target="$downloads_dir/$(basename "$DMG_PATH")"
publish_dmg_copy="${PUBLISH_DMG_COPY:-1}"

[[ -f "$DMG_PATH" ]] || fail "DMG not found at $DMG_PATH. Run create-dmg.sh first."

validate_beta_semver_progression() {
  [[ "$RELEASE_CHANNEL" == "beta" ]] || return 0
  [[ "${ALLOW_POST_STABLE_BETA_FOR_SAME_VERSION:-0}" == "1" ]] && return 0

  local stable_latest_path="$RELEASE_DIR/live-stable-latest.json"
  if ! curl -fsSL "$DIST_BASE_URL/stable/latest.json" -o "$stable_latest_path"; then
    rm -f "$stable_latest_path"
    return 0
  fi

  local comparison
  comparison="$(
    node -e '
      const fs = require("fs");

      const betaVersion = process.argv[1];
      const stableLatestPath = process.argv[2];

      function parseSemver(raw) {
        return String(raw)
          .trim()
          .split(".")
          .map((part) => Number.parseInt(part, 10));
      }

      function compareSemver(a, b) {
        const aParts = parseSemver(a);
        const bParts = parseSemver(b);
        const length = Math.max(aParts.length, bParts.length);
        for (let index = 0; index < length; index += 1) {
          const left = Number.isFinite(aParts[index]) ? aParts[index] : 0;
          const right = Number.isFinite(bParts[index]) ? bParts[index] : 0;
          if (left > right) {
            return 1;
          }
          if (left < right) {
            return -1;
          }
        }
        return 0;
      }

      const stableLatest = JSON.parse(fs.readFileSync(stableLatestPath, "utf8"));
      const stableVersion = String(stableLatest.version ?? "").trim();

      if (!stableVersion) {
        process.stdout.write("skip");
        process.exit(0);
      }

      if (compareSemver(stableVersion, betaVersion) >= 0) {
        process.stdout.write(stableVersion);
        process.exit(0);
      }

      process.stdout.write("ok");
    ' "$APP_VERSION" "$stable_latest_path"
  )"
  rm -f "$stable_latest_path"

  [[ "$comparison" == "ok" || "$comparison" == "skip" ]] && return 0

  fail "stable $comparison is already live at $DIST_BASE_URL/stable/latest.json. Publishing beta ${APP_VERSION}-beta.${APP_BUILD} would be numerically lower than the installed stable build for that version range, so Sparkle cannot move stable installs onto it. Publish the next beta under a higher semver (for example 1.0.1-beta.1) or set ALLOW_POST_STABLE_BETA_FOR_SAME_VERSION=1 to override."
}

prepare_site_root() {
  mkdir -p "$downloads_root"
  rm -rf "$downloads_root/app" "$downloads_root/public" "$downloads_root/.next" "$downloads_root/node_modules"
  rm -f "$downloads_root/package-lock.json" "$downloads_root/tsconfig.tsbuildinfo" "$downloads_root/.DS_Store"
  cp -R "$SCRIPT_DIR/templates/site-app/." "$downloads_root/"
  rm -rf "$downloads_root/.next" "$downloads_root/node_modules"
  rm -f "$downloads_root/tsconfig.tsbuildinfo" "$downloads_root/.DS_Store"
}

channel_file_url() {
  local channel="$1"
  local relative_path="$2"
  printf '%s/%s/%s\n' "$DIST_BASE_URL" "$channel" "$relative_path"
}

restore_channel_from_manifest() {
  local channel="$1"
  local target_root="$public_root/$channel"
  local temp_manifest="$RELEASE_DIR/restore-${channel}-manifest.json"

  mkdir -p "$target_root"
  if ! curl -fsSL "$DIST_BASE_URL/$channel/manifest.json" -o "$temp_manifest"; then
    rm -f "$temp_manifest"
    return 1
  fi

  cp "$temp_manifest" "$target_root/manifest.json"

  local relative_path
  while IFS= read -r relative_path; do
    [[ -n "$relative_path" ]] || continue
    mkdir -p "$(dirname "$target_root/$relative_path")"
    curl -fsSL "$(channel_file_url "$channel" "$relative_path")" -o "$target_root/$relative_path"
  done < <(
    node -e '
      const fs = require("fs");
      const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      for (const file of manifest.files ?? []) {
        console.log(file);
      }
    ' "$temp_manifest"
  )

  rm -f "$temp_manifest"
}

bootstrap_channel_from_live_site() {
  local channel="$1"
  local target_root="$public_root/$channel"
  local latest_path="$target_root/latest.json"
  local appcast_path="$target_root/appcast.xml"
  local sha_path="$target_root/sha256.txt"

  mkdir -p "$target_root"

  if ! curl -fsSL "$DIST_BASE_URL/$channel/latest.json" -o "$latest_path"; then
    rm -f "$latest_path" "$appcast_path" "$sha_path" "$target_root/sparkle-item.json" "$target_root/manifest.json"
    rm -rf "$target_root/downloads" "$target_root/release-notes"
    return 0
  fi

  curl -fsSL "$DIST_BASE_URL/$channel/appcast.xml" -o "$appcast_path" || true
  curl -fsSL "$DIST_BASE_URL/$channel/sha256.txt" -o "$sha_path" || true

  local release_notes_slug
  release_notes_slug="$(
    node -e '
      const fs = require("fs");
      const latest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const value = String(latest.releaseNotesUrl ?? "").replace(/\.html$/i, "");
      const slug = value.split("/").filter(Boolean).pop() ?? "";
      process.stdout.write(slug);
    ' "$latest_path"
  )"
  if [[ -n "$release_notes_slug" ]]; then
    mkdir -p "$target_root/release-notes"
    curl -fsSL "$DIST_BASE_URL/$channel/release-notes/${release_notes_slug}.html" \
      -o "$target_root/release-notes/${release_notes_slug}.html" || true
  fi

  local legacy_release_notes_name
  legacy_release_notes_name="$(
    node -e '
      const fs = require("fs");
      const latest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const version = String(latest.version ?? "").trim();
      process.stdout.write(version);
    ' "$latest_path"
  )"
  if [[ "$channel" == "beta" && -n "$release_notes_slug" && -n "$legacy_release_notes_name" && "$legacy_release_notes_name" != "$release_notes_slug" && -f "$target_root/release-notes/${release_notes_slug}.html" ]]; then
    cp "$target_root/release-notes/${release_notes_slug}.html" "$target_root/release-notes/${legacy_release_notes_name}.html"
  fi

  local dmg_name
  dmg_name="$(
    node -e '
      const fs = require("fs");
      const latest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const downloadUrl = String(latest.downloadUrl ?? "");
      const parts = downloadUrl.split("/").filter(Boolean);
      process.stdout.write(parts.pop() ?? "");
    ' "$latest_path"
  )"
  if [[ -n "$dmg_name" ]]; then
    mkdir -p "$target_root/downloads"
    curl -fsSL "$DIST_BASE_URL/$channel/downloads/${dmg_name}" -o "$target_root/downloads/${dmg_name}" || true
  fi

  node -e '
    const fs = require("fs");
    const path = require("path");

    const targetRoot = process.argv[1];
    const channel = process.argv[2];

    const latestPath = path.join(targetRoot, "latest.json");
    const appcastPath = path.join(targetRoot, "appcast.xml");
    if (!fs.existsSync(latestPath) || !fs.existsSync(appcastPath)) {
      process.exit(0);
    }

    const latest = JSON.parse(fs.readFileSync(latestPath, "utf8"));
    const appcast = fs.readFileSync(appcastPath, "utf8");

    const itemMatch = appcast.match(/<item>([\s\S]*?)<\/item>/i);
    if (!itemMatch) {
      process.exit(0);
    }

    const itemXml = itemMatch[1];
    const tagValue = (tag) => {
      const match = itemXml.match(new RegExp(`<${tag}>([\\s\\S]*?)<\\/${tag}>`, "i"));
      return match ? match[1].trim() : "";
    };

    const titleMatch = itemXml.match(/<title>([\s\S]*?)<\/title>/i);
    const enclosureMatch = itemXml.match(/<enclosure\s+([^>]+?)\/>/i);
    const enclosureAttrs = enclosureMatch ? enclosureMatch[1] : "";
    const attrValue = (name) => {
      const match = enclosureAttrs.match(new RegExp(`${name}="([^"]*)"`, "i"));
      return match ? match[1] : "";
    };

    const sparkleItem = {
      channel,
      title: titleMatch ? titleMatch[1].trim() : `10x ${latest.version}`,
      link: `${String(latest.downloadUrl ?? "").split("/").slice(0, -2).join("/")}/`,
      description: channel === "beta" ? "10x beta update feed." : "10x stable update feed.",
      version: tagValue("sparkle:version") || String(latest.bundleVersion ?? ""),
      shortVersionString: tagValue("sparkle:shortVersionString") || String(latest.version ?? ""),
      minimumSystemVersion: tagValue("sparkle:minimumSystemVersion") || "14.0.0",
      releaseNotesLink: tagValue("sparkle:releaseNotesLink") || `${latest.releaseNotesUrl}.html`,
      pubDate: tagValue("pubDate"),
      sparkleChannel: channel === "beta" ? "beta" : null,
      enclosure: {
        url: attrValue("url") || String(latest.downloadUrl ?? ""),
        length: attrValue("length") || "",
        edSignature: attrValue("sparkle:edSignature") || "",
        type: attrValue("type") || "application/octet-stream",
      },
    };

    fs.writeFileSync(
      path.join(targetRoot, "sparkle-item.json"),
      `${JSON.stringify(sparkleItem, null, 2)}\n`,
    );
  ' "$target_root" "$channel"
}

prepare_release_notes_source() {
  if [[ -z "$release_notes_source" && -f "$RELEASE_NOTES_PATH_REPO_BUILD_DEFAULT" ]]; then
    release_notes_source="$RELEASE_NOTES_PATH_REPO_BUILD_DEFAULT"
  fi
  if [[ -z "$release_notes_source" && -f "$RELEASE_NOTES_PATH_REPO_DEFAULT" ]]; then
    release_notes_source="$RELEASE_NOTES_PATH_REPO_DEFAULT"
  fi
  if [[ -z "$release_notes_source" ]]; then
    release_notes_source="$RELEASE_NOTES_PATH_DEFAULT"
  fi

  if [[ -f "$release_notes_source" ]]; then
    return
  fi

  published_at_human=$(date -u +"%B %d, %Y")
  build_label="$APP_VERSION"
  if [[ "$RELEASE_CHANNEL" == "beta" ]]; then
    build_label="$APP_VERSION Beta $APP_BUILD"
  fi

  cat > "$release_notes_source" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${APP_NAME} ${build_label}</title>
    <style>
      body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        margin: 0;
        padding: 48px 20px;
        background: #0d1726;
        color: #f5f7fb;
      }
      main {
        max-width: 720px;
        margin: 0 auto;
      }
      h1 {
        margin-bottom: 8px;
      }
      p,
      li {
        color: rgba(245, 247, 251, 0.82);
        line-height: 1.6;
      }
      code {
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>${APP_NAME} ${build_label}</h1>
      <p>Published ${published_at_human} UTC.</p>
      <p>This is a placeholder release note. Replace <code>${release_notes_source}</code> before publishing externally if you want richer notes.</p>
    </main>
  </body>
</html>
EOF
}

write_channel_manifest() {
  local channel="$1"
  local target_root="$public_root/$channel"
  local manifest_path="$target_root/manifest.json"
  local files_json

  mkdir -p "$target_root"

  files_json="$(
    cd "$target_root"
    find . -type f ! -name 'manifest.json' | sed 's#^\./##' | sort | node -e '
      const fs = require("fs");
      const files = fs.readFileSync(0, "utf8")
        .split(/\n+/)
        .map((value) => value.trim())
        .filter(Boolean);
      process.stdout.write(JSON.stringify(files, null, 2));
    '
  )"

  cat > "$manifest_path" <<EOF
{
  "channel": "$channel",
  "files": $files_json
}
EOF
}

render_appcasts() {
  node -e '
    const fs = require("fs");
    const path = require("path");

    const publicRoot = process.argv[1];
    const distBaseUrl = process.argv[2];

    const escapeXml = (value) => String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'\''/g, "&apos;");

    const channelConfig = {
      stable: {
        title: "10x Stable Updates",
        description: "10x stable update feed.",
        link: `${distBaseUrl}/stable/`,
      },
      beta: {
        title: "10x Beta Updates",
        description: "10x beta update feed.",
        link: `${distBaseUrl}/beta/`,
      },
    };

    const loadItem = (channel) => {
      const filePath = path.join(publicRoot, channel, "sparkle-item.json");
      if (!fs.existsSync(filePath)) {
        return null;
      }
      return JSON.parse(fs.readFileSync(filePath, "utf8"));
    };

    const renderItem = (item) => {
      const enclosureAttributes = [
        `url="${escapeXml(item.enclosure?.url ?? "")}"`,
        item.enclosure?.edSignature
          ? `sparkle:edSignature="${escapeXml(item.enclosure.edSignature)}"`
          : null,
        item.enclosure?.length
          ? `length="${escapeXml(item.enclosure.length)}"`
          : null,
        `type="${escapeXml(item.enclosure?.type ?? "application/octet-stream")}"`,
      ]
        .filter(Boolean)
        .join(" ");

      const sparkleChannel = item.sparkleChannel
        ? `\n      <sparkle:channel>${escapeXml(item.sparkleChannel)}</sparkle:channel>`
        : "";

      return `    <item>
      <title>${escapeXml(item.title)}</title>
      <link>${escapeXml(item.link)}</link>
      <sparkle:version>${escapeXml(item.version)}</sparkle:version>
      <sparkle:shortVersionString>${escapeXml(item.shortVersionString)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${escapeXml(item.minimumSystemVersion)}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>${escapeXml(item.releaseNotesLink)}</sparkle:releaseNotesLink>${sparkleChannel}
      <pubDate>${escapeXml(item.pubDate)}</pubDate>
      <enclosure ${enclosureAttributes} />
    </item>`;
    };

    const renderFeed = (title, description, link, items) => `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${escapeXml(title)}</title>
    <link>${escapeXml(link)}</link>
    <description>${escapeXml(description)}</description>
    <language>en</language>
${items.map(renderItem).join("\n")}
  </channel>
</rss>
`;

    const stableItem = loadItem("stable");
    const betaItem = loadItem("beta");

    for (const channel of ["stable", "beta"]) {
      const item = channel === "stable" ? stableItem : betaItem;
      const config = channelConfig[channel];
      const targetPath = path.join(publicRoot, channel, "appcast.xml");
      fs.mkdirSync(path.dirname(targetPath), { recursive: true });
      if (!item) {
        fs.writeFileSync(targetPath, renderFeed(config.title, config.description, config.link, []));
        continue;
      }
      fs.writeFileSync(targetPath, renderFeed(config.title, config.description, config.link, [item]));
    }

    const canonicalPath = path.join(publicRoot, "appcast.xml");
    fs.writeFileSync(
      canonicalPath,
      renderFeed(
        "10x Updates",
        "10x stable and beta update feed.",
        distBaseUrl,
        [stableItem, betaItem].filter(Boolean),
      ),
    );
  ' "$public_root" "$DIST_BASE_URL"
}

validate_beta_semver_progression
prepare_site_root
restore_channel_from_manifest "stable" || bootstrap_channel_from_live_site "stable"
restore_channel_from_manifest "beta" || bootstrap_channel_from_live_site "beta"
prepare_release_notes_source

mkdir -p "$release_notes_dir"
if [[ "$publish_dmg_copy" != "0" ]]; then
  mkdir -p "$downloads_dir"
fi

if [[ "$publish_dmg_copy" != "0" ]]; then
  cp "$DMG_PATH" "$dmg_target"
fi
cp "$release_notes_source" "$release_notes_target"
if [[ "$RELEASE_CHANNEL" == "beta" ]]; then
  cp "$release_notes_source" "$release_notes_dir/${APP_VERSION}.html"
fi

sha256=$(shasum -a 256 "$DMG_PATH" | awk "{print \$1}")
published_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
pub_date_rfc2822=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
download_url="${DOWNLOAD_URL_OVERRIDE:-$RELEASE_CHANNEL_BASE_URL/downloads/$(basename "$DMG_PATH")}"
release_notes_site_url="${RELEASE_NOTES_URL_OVERRIDE:-$RELEASE_CHANNEL_BASE_URL/release-notes/${RELEASE_NOTES_SLUG}}"
sparkle_release_notes_url="${SPARKLE_RELEASE_NOTES_URL_OVERRIDE:-$RELEASE_CHANNEL_BASE_URL/release-notes/${RELEASE_NOTES_SLUG}.html}"
file_size=$(stat -f "%z" "$DMG_PATH")

cat > "$channel_root/latest.json" <<EOF
{
  "channel": "${RELEASE_CHANNEL}",
  "version": "${APP_VERSION}",
  "build": "${APP_BUILD}",
  "bundleVersion": "${INTERNAL_BUNDLE_VERSION}",
  "publishedAt": "${published_at}",
  "releaseNotesUrl": "${release_notes_site_url}",
  "sha256": "${sha256}",
  "downloadUrl": "${download_url}"
}
EOF

cat > "$channel_root/sha256.txt" <<EOF
${sha256}  $(basename "$DMG_PATH")
EOF

sign_update=""
if sparkle_bin_dir=$(maybe_find_sparkle_bin_dir); then
  if [[ -x "$sparkle_bin_dir/sign_update" ]]; then
    sign_update="$sparkle_bin_dir/sign_update"
  fi
fi

enclosure_signature=""
if [[ -n "$sign_update" ]]; then
  sign_update_args=(--account "$SPARKLE_KEYCHAIN_ACCOUNT")
  if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    sign_update_args=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
  elif [[ -n "${SPARKLE_PRIVATE_KEY_BASE64:-}" ]]; then
    sparkle_private_key_file="$RELEASE_DIR/sparkle_private_key.txt"
    printf '%s' "$SPARKLE_PRIVATE_KEY_BASE64" > "$sparkle_private_key_file"
    chmod 600 "$sparkle_private_key_file"
    sign_update_args=(--ed-key-file "$sparkle_private_key_file")
  fi

  enclosure_attrs=$("$sign_update" "${sign_update_args[@]}" "$DMG_PATH")
  if [[ "$enclosure_attrs" =~ sparkle:edSignature=\"([^\"]+)\" ]]; then
    enclosure_signature="${BASH_REMATCH[1]}"
  fi
fi

release_item_title="$APP_NAME $APP_VERSION"
if [[ "$RELEASE_CHANNEL" == "beta" ]]; then
  release_item_title="$APP_NAME $APP_VERSION Beta $APP_BUILD"
fi

cat > "$channel_root/sparkle-item.json" <<EOF
{
  "channel": "${RELEASE_CHANNEL}",
  "title": "${release_item_title}",
  "link": "${RELEASE_CHANNEL_BASE_URL}/",
  "description": "${APP_NAME} ${RELEASE_CHANNEL_DESCRIPTION} update feed.",
  "version": "${INTERNAL_BUNDLE_VERSION}",
  "shortVersionString": "${APP_VERSION}",
  "minimumSystemVersion": "14.0.0",
  "releaseNotesLink": "${sparkle_release_notes_url}",
  "pubDate": "${pub_date_rfc2822}",
  "sparkleChannel": $([[ "$RELEASE_CHANNEL" == "beta" ]] && printf '"beta"' || printf 'null'),
  "enclosure": {
    "url": "${download_url}",
    "length": "${file_size}",
    "edSignature": "${enclosure_signature}",
    "type": "application/octet-stream"
  }
}
EOF

render_appcasts
write_channel_manifest "stable"
write_channel_manifest "beta"

log "Published ${RELEASE_CHANNEL} artifacts into $channel_root"
