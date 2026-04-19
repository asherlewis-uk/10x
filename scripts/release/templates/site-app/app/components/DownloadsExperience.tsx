"use client";

import BottomNav from "./BottomNav";
import Dither from "./Dither";
import BuilderMark from "./BuilderMark";
import DownloadsDock from "./DownloadsDock";
import { channelDisplayName, type ReleaseChannel } from "../lib/channels";

type DownloadsExperienceProps = {
  channel: ReleaseChannel;
};

export default function DownloadsExperience({ channel }: DownloadsExperienceProps) {
  const channelName = channelDisplayName(channel);

  return (
    <>
      <div className="dither-layer">
        <Dither
          waveColor={[0.24, 0.24, 0.24]}
          disableAnimation={false}
          enableMouseInteraction={true}
          mouseRadius={0}
          colorNum={4}
          pixelSize={5}
          waveAmplitude={0.16}
          waveFrequency={0.22}
          waveSpeed={0.03}
        />
      </div>

      <main className="scene">
        <div className="star-stage">
          <BuilderMark className="downloads-mark" />
          <p className="downloads-badge">
            <span className="smallcaps">{channelName} Downloads</span>
          </p>
          <div className="platform-callout" role="note" aria-label="Platform support">
            <span className="platform-icon">
              <svg viewBox="0 0 24 24" role="presentation" focusable="false">
                <path d="M16.365 12.86c.02 2.11 1.848 2.813 1.868 2.821-.015.05-.292 1.007-.964 1.996-.58.855-1.182 1.707-2.13 1.725-.932.017-1.232-.553-2.298-.553-1.067 0-1.4.536-2.281.57-.915.034-1.611-.918-2.195-1.77-1.192-1.739-2.103-4.915-.88-7.04.607-1.055 1.691-1.723 2.868-1.74.898-.018 1.747.604 2.298.604.55 0 1.586-.747 2.672-.638.454.019 1.73.183 2.549 1.381-.066.041-1.522.887-1.507 2.644Zm-2.01-5.117c.486-.589.813-1.409.723-2.223-.7.028-1.547.467-2.049 1.056-.45.52-.843 1.355-.736 2.153.78.061 1.576-.396 2.061-.986Z" />
              </svg>
            </span>
            <div className="platform-copy">
              <p className="platform-label">
                <span className="smallcaps">Platform</span>
              </p>
              <p className="platform-title">Only supported on macOS</p>
            </div>
          </div>
        </div>
      </main>

      <DownloadsDock channel={channel} />
      <BottomNav channel={channel} />
    </>
  );
}
