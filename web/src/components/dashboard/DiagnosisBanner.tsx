import type { RootCause } from '@/lib/analytics'

export default function DiagnosisBanner({
  name,
  rootCause,
  confidentlyWrong,
}: {
  name: string
  rootCause: RootCause | null
  confidentlyWrong: number
}) {
  return (
    <div className="border border-rule bg-card">
      <div className="border-b border-rule px-6 py-3 flex flex-wrap items-center justify-between gap-3">
        <span className="font-mono text-[10px] eyebrow text-faint">DIAGNOSIS</span>
        {confidentlyWrong > 0 && (
          <span className="font-mono text-[10px] text-alarm">
            {confidentlyWrong} CONFIDENTLY WRONG
          </span>
        )}
      </div>

      <div className="px-6 py-7">
        <p className="font-mono text-[11px] eyebrow text-faint mb-4">
          {name.split(' ')[0].toUpperCase()}, START HERE
        </p>

        {!rootCause ? (
          <>
            <h1 className="font-display font-extrabold text-2xl md:text-[2rem] tight leading-tight max-w-2xl">
              Nothing has failed enough to trace yet.
            </h1>
            <p className="mt-4 text-soft leading-relaxed max-w-xl">
              Root-cause attribution needs failures to propagate. Answer more questions
              and the graph will start pointing somewhere.
            </p>
          </>
        ) : (
          <>
            {rootCause.isTraced ? (
              <>
                <h1 className="font-display font-extrabold text-2xl md:text-[2rem] tight leading-tight max-w-2xl">
                  Your {rootCause.failedConcept} failures trace down to{' '}
                  <span className="text-amber">{rootCause.rootConcept}</span>.
                </h1>
                <p className="mt-4 text-soft leading-relaxed max-w-xl">
                  {rootCause.failures} failure{rootCause.failures === 1 ? '' : 's'} on{' '}
                  {rootCause.failedConcept}. {Math.round(rootCause.share * 100)}% of the
                  blame lands on its weakest prerequisite, and the chain bottoms out at{' '}
                  {rootCause.rootConcept} (mastery{' '}
                  {rootCause.rootMastery.toFixed(2)}).
                </p>
              </>
            ) : (
              <>
                <h1 className="font-display font-extrabold text-2xl md:text-[2rem] tight leading-tight max-w-2xl">
                  <span className="text-amber">{rootCause.failedConcept}</span> is the gap
                  itself.
                </h1>
                <p className="mt-4 text-soft leading-relaxed max-w-xl">
                  {rootCause.failures} failure{rootCause.failures === 1 ? '' : 's'} here,
                  but every prerequisite is already solid. Nothing underneath is holding
                  you back, so this is worth attacking directly rather than going a level
                  down.
                </p>
              </>
            )}

            <div className="mt-6 border-t border-rule pt-5">
              <p className="font-mono text-[10px] eyebrow text-faint mb-4">
                {rootCause.isTraced ? 'BLAME TRACE' : 'PREREQUISITES CHECKED'}
              </p>
              <ol className="space-y-2.5">
                {rootCause.trace.map((s, i) => (
                  <li key={s.conceptId} className="flex items-center gap-4">
                    <span className="font-mono text-[10px] text-faint w-4 shrink-0">
                      {i === 0 ? 'x' : '>'}
                    </span>
                    <span className="font-mono text-xs w-44 shrink-0 truncate">
                      {s.concept}
                    </span>
                    <div className="flex-1 h-1.5 bg-rule relative min-w-[3rem]">
                      <div
                        className={i === rootCause.trace.length - 1 ? 'bg-amber' : 'bg-faint'}
                        style={{
                          width: `${s.share * 100}%`,
                          position: 'absolute',
                          inset: '0 auto 0 0',
                        }}
                      />
                    </div>
                    <span className="font-mono text-[10px] text-faint w-24 text-right shrink-0">
                      {Math.round(s.share * 100)}% &middot; m{s.mastery.toFixed(2)}
                    </span>
                  </li>
                ))}
              </ol>
              <p className="font-mono text-[10px] text-faint mt-4">
                {rootCause.isTraced
                  ? 'blame = edge weight \u00d7 (1 \u2212 mastery) \u00d7 uncertainty, normalised per level'
                  : 'propagation stopped: every prerequisite is above the 0.80 mastery threshold'}
              </p>
            </div>
          </>
        )}
      </div>
    </div>
  )
}