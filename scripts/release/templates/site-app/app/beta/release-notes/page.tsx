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

export default async function ReleaseNotesIndexPage() {
  const latest = await readLatestRelease("beta");
  const notes = await readReleaseNotes("beta", extractReleaseNotesSlug(latest?.releaseNotesUrl) ?? latest?.version);
  const versionLabel = notes
    ? formatReleaseVersionLabel("beta", notes.version, notes.build)
    : latest
      ? formatReleaseVersionLabel("beta", latest.version, latest.build)
      : "Release Notes";

  return (
    <ReleaseNotesLayout
      channel="beta"
      versionLabel={versionLabel}
      publishedAt={formatPublishedAt(latest?.publishedAt)}
      html={
        notes?.html ??
        "<p>No release notes are available yet. Publish a beta build to populate this page.</p>"
      }
    />
  );
}
