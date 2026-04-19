export type ReleaseChannel = "stable" | "beta";

export function channelBasePath(channel: ReleaseChannel) {
  return channel === "stable" ? "/stable" : "/beta";
}

export function channelDisplayName(channel: ReleaseChannel) {
  return channel === "stable" ? "Stable" : "Beta";
}

export function channelReleaseNotesIndexPath(channel: ReleaseChannel) {
  return `${channelBasePath(channel)}/release-notes`;
}
