import { notFound } from "next/navigation";
import ReleaseNotesLayout from "../../../components/ReleaseNotesLayout";
import { extractReleaseNotesSlug, formatReleaseVersionLabel, readLatestRelease, readReleaseNotes } from "../../../lib/release-data";

type VersionPageProps = {
  params: Promise<{
    version: string;
  }>;
};

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

export default async function ReleaseNotesVersionPage({ params }: VersionPageProps) {
  const { version } = await params;
  const normalizedVersion = version.replace(/\.html$/i, "");
  const latest = await readLatestRelease("beta");
  const notes = await readReleaseNotes("beta", normalizedVersion);

  if (!notes) {
    notFound();
  }

  const buildLabel = formatReleaseVersionLabel("beta", notes.version, notes.build ?? latest?.build);

  const latestSlug = extractReleaseNotesSlug(latest?.releaseNotesUrl);
  const publishedAt =
    latestSlug === notes.slug || (latest?.version === notes.version && !notes.build)
      ? formatPublishedAt(latest?.publishedAt)
      : null;

  return (
    <ReleaseNotesLayout
      channel="beta"
      versionLabel={buildLabel}
      publishedAt={publishedAt}
      html={notes.html}
    />
  );
}
