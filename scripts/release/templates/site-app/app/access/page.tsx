import BottomNav from "../components/BottomNav";
import Dither from "../components/Dither";
import BuilderMark from "../components/BuilderMark";

type AccessPageProps = {
  searchParams?: Promise<{
    error?: string;
    next?: string;
  }>;
};

export default async function AccessPage({ searchParams }: AccessPageProps) {
  const resolved = (await searchParams) ?? {};
  const nextPath = resolved.next && resolved.next.startsWith("/") ? resolved.next : "/stable";
  const showError = resolved.error === "1";

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
        <section className="access-shell">
          <div className="access-mark" aria-hidden="true">
            <BuilderMark className="downloads-mark" />
          </div>
          <p className="access-label">
            <span className="smallcaps">Downloads Access</span>
          </p>
          <form className="access-form" action="/api/access" method="post">
            <input type="hidden" name="next" value={nextPath} />
            <label className="access-field">
              <span className="sr-only">Access code</span>
              <input
                name="accessCode"
                type="password"
                autoFocus
                spellCheck={false}
                autoCapitalize="characters"
                autoCorrect="off"
                placeholder="Enter access code"
              />
            </label>
            <button type="submit" className="action-button action-button-primary">
              <span className="smallcaps">Enter</span>
            </button>
          </form>
          {showError ? (
            <p className="access-error">
              <span className="smallcaps">Invalid access code.</span>
            </p>
          ) : null}
        </section>
      </main>
      <BottomNav channel="stable" />
    </>
  );
}
