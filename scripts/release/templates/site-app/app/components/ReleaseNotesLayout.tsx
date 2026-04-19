import BottomNav from "./BottomNav";
import Dither from "./Dither";
import BuilderMark from "./BuilderMark";
import type { ReleaseChannel } from "../lib/channels";

type ReleaseNotesLayoutProps = {
  channel: ReleaseChannel;
  versionLabel: string;
  publishedAt?: string | null;
  html: string;
};

export default function ReleaseNotesLayout({
  channel,
  versionLabel,
  publishedAt,
  html,
}: ReleaseNotesLayoutProps) {
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

      <main className="notes-page">
        <div className="notes-scroll">
          <div className="notes-header">
            <div className="notes-mark" aria-hidden="true">
              <BuilderMark className="downloads-mark" />
            </div>
            <p className="notes-kicker">
              <span className="smallcaps">Release Notes</span>
            </p>
            <h1 className="notes-title">
              <span className="smallcaps">{versionLabel}</span>
            </h1>
            {publishedAt ? <p className="notes-subtitle">{publishedAt}</p> : null}
          </div>

          <article
            className="notes-content"
            dangerouslySetInnerHTML={{ __html: html }}
          />
        </div>
      </main>
      <BottomNav channel={channel} />
    </>
  );
}
