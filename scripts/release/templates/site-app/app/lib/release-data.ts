import { promises as fs } from "fs";
import path from "path";
import type { ReleaseChannel } from "./channels";

export type LatestRelease = {
  channel?: string;
  version: string;
  build: string;
  bundleVersion?: string;
  publishedAt: string;
  releaseNotesUrl: string;
  sha256: string;
  downloadUrl: string;
};

function channelPublicPath(channel: ReleaseChannel, ...parts: string[]) {
  return path.join(process.cwd(), "public", channel, ...parts);
}

function normalizeReleaseNotesSlug(value: string) {
  const trimmed = value.trim().replace(/\.html$/i, "");
  if (!trimmed) {
    return "";
  }

  return trimmed.split("/").filter(Boolean).pop() ?? "";
}

export function extractReleaseNotesSlug(value: string | null | undefined) {
  if (!value) {
    return null;
  }

  return normalizeReleaseNotesSlug(value) || null;
}

function parseReleaseNotesSlug(channel: ReleaseChannel, slug: string) {
  if (channel !== "beta") {
    return {
      version: slug,
      build: null as string | null,
    };
  }

  const match = slug.match(/^(.*)-beta\.(\d+)$/i);
  if (!match) {
    return {
      version: slug,
      build: null as string | null,
    };
  }

  return {
    version: match[1],
    build: match[2],
  };
}

export function formatReleaseVersionLabel(channel: ReleaseChannel, version: string, build?: string | null) {
  if (channel === "beta" && build) {
    return `10X ${version} Beta ${build}`;
  }

  return `10X ${version}`;
}

export async function readLatestRelease(channel: ReleaseChannel): Promise<LatestRelease | null> {
  try {
    const raw = await fs.readFile(channelPublicPath(channel, "latest.json"), "utf8");
    return JSON.parse(raw) as LatestRelease;
  } catch {
    return null;
  }
}

function extractMainContent(html: string) {
  const mainMatch = html.match(/<main[^>]*>([\s\S]*?)<\/main>/i);
  if (mainMatch?.[1]) {
    return mainMatch[1].trim();
  }
  const bodyMatch = html.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
  if (bodyMatch?.[1]) {
    return bodyMatch[1].trim();
  }
  return html.trim();
}

export async function readReleaseNotes(channel: ReleaseChannel, version?: string) {
  const latest = await readLatestRelease(channel);
  const latestSlug = extractReleaseNotesSlug(latest?.releaseNotesUrl);
  const resolvedSlug = normalizeReleaseNotesSlug(version ?? latestSlug ?? latest?.version ?? "");

  if (!resolvedSlug) {
    return null;
  }

  try {
    const raw = await fs.readFile(channelPublicPath(channel, "release-notes", `${resolvedSlug}.html`), "utf8");
    const parsed = parseReleaseNotesSlug(channel, resolvedSlug);
    return {
      channel,
      slug: resolvedSlug,
      version: parsed.version,
      build: parsed.build,
      latest,
      html: extractMainContent(raw),
    };
  } catch {
    return null;
  }
}
