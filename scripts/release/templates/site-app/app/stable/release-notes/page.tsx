import ReleaseNotesLayout from "../../components/ReleaseNotesLayout";
import { extractReleaseNotesSlug, formatReleaseVersionLabel, readLatestRelease, readReleaseNotes } from "../../lib/release-data";

function formatPublishedAt(value: string | null | undefined) {
  if (!value) return null;
  const published = new Date(value);
  if (Number.isNaN(published.valueOf())) {
    return value;
  }

  return `${published.toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  })} UTC`;
}

export default async function StableReleaseNotesIndexPage() {
  const latest = await readLatestRelease("stable");
  const notes = await readReleaseNotes("stable", extractReleaseNotesSlug(latest?.releaseNotesUrl) ?? latest?.version);
  const versionLabel = notes
    ? formatReleaseVersionLabel("stable", notes.version, notes.build)
    : latest
      ? formatReleaseVersionLabel("stable", latest.version, latest.build)
      : "Release Notes";

  return (
    <ReleaseNotesLayout
      channel="stable"
      versionLabel={versionLabel}
      publishedAt={formatPublishedAt(latest?.publishedAt)}
      html={
        notes?.html ??
        "<p>No release notes are available yet. Publish a stable build to populate this page.</p>"
      }
    />
  );
}
