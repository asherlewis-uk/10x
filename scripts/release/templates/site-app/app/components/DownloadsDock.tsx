"use client";

import { motion } from "motion/react";
import { useEffect, useState } from "react";
import { channelBasePath, channelDisplayName, channelReleaseNotesIndexPath, type ReleaseChannel } from "../lib/channels";

type LatestRelease = {
  channel?: string;
  version: string;
  build: string;
  bundleVersion?: string;
  publishedAt: string;
  releaseNotesUrl: string;
  sha256: string;
  downloadUrl: string;
};

type DownloadsDockProps = {
  channel: ReleaseChannel;
};

export default function DownloadsDock({ channel }: DownloadsDockProps) {
  const [latest, setLatest] = useState<LatestRelease | null>(null);
  const [fallbackLatest, setFallbackLatest] = useState<LatestRelease | null>(null);
  const [error, setError] = useState(false);
  const channelName = channelDisplayName(channel);
  const channelBase = channelBasePath(channel);
  const releaseNotesIndexPath = channelReleaseNotesIndexPath(channel);
  const betaBase = channelBasePath("beta");
  const betaReleaseNotesIndexPath = channelReleaseNotesIndexPath("beta");

  useEffect(() => {
    let active = true;

    const loadLatest = async (basePath: string) => {
      const response = await fetch(`${basePath}/latest.json`, { cache: "no-store" });
      if (!response.ok) {
        return {
          ok: false,
          notFound: response.status === 404,
          data: null,
        };
      }

      return {
        ok: true,
        notFound: false,
        data: await response.json() as LatestRelease,
      };
    };

    const load = async () => {
      try {
        setError(false);
        setLatest(null);
        setFallbackLatest(null);

        const primary = await loadLatest(channelBase);
        if (!active) return;

        if (primary.ok && primary.data) {
          setLatest(primary.data);
          return;
        }

        if (channel === "stable" && primary.notFound) {
          const beta = await loadLatest(betaBase);
          if (!active) return;

          if (beta.ok && beta.data) {
            setFallbackLatest(beta.data);
            return;
          }
        }

        setError(true);
      } catch {
        if (!active) return;
        setError(true);
      }
    };

    void load();

    return () => {
      active = false;
    };
  }, [betaBase, channel, channelBase]);

  const effectiveChannel: ReleaseChannel = fallbackLatest ? "beta" : channel;
  const effectiveLatest = latest ?? fallbackLatest;
  const effectiveReleaseNotesIndexPath =
    effectiveChannel === "beta" ? betaReleaseNotesIndexPath : releaseNotesIndexPath;

  const statusLabel = effectiveLatest
    ? effectiveChannel === "beta"
      ? channel === "stable" && fallbackLatest
        ? `Stable not published yet. Beta ${effectiveLatest.version} Build ${effectiveLatest.build} is available`
        : `${channelDisplayName(effectiveChannel)} ${effectiveLatest.version} Build ${effectiveLatest.build}`
      : `${channelDisplayName(effectiveChannel)} ${effectiveLatest.version}`
    : error
      ? channel === "stable"
        ? "Stable release not published yet"
        : `${channelName} metadata unavailable`
      : `Loading ${channelName.toLowerCase()} release`;

  const primaryLabel = effectiveChannel === "beta" ? "Download Beta for macOS" : "Download 10x for macOS";
  const primaryHref = effectiveLatest?.downloadUrl ?? (effectiveChannel === "beta" ? betaBase : channelBase);
  const releaseNotesHref = effectiveLatest?.releaseNotesUrl ?? effectiveReleaseNotesIndexPath;

  return (
    <div className="downloads-actions-anchor">
      <motion.section
        className="downloads-actions-shell"
        id="downloads"
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.9, delay: 0.35, ease: "easeOut" }}
      >
        <p className="downloads-status">
          <span className="smallcaps">{statusLabel}</span>
        </p>
        <a className="action-button action-button-primary" href={primaryHref}>
          <span className="smallcaps">{primaryLabel}</span>
        </a>
        <a className="downloads-secondary-link" href={releaseNotesHref}>
          <span className="smallcaps">Release Notes</span>
        </a>
      </motion.section>
    </div>
  );
}
