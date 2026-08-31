export default function MasteryBar({
  mastery,
  observations,
}: {
  mastery: number
  observations: number
}) {
  const thin = observations < 4
  const color = mastery < 0.4 ? 'bg-alarm' : mastery < 0.7 ? 'bg-amber' : 'bg-mastery'

  // Rough interval: shrinks as observations accumulate. Communicates
  // "we are not sure yet" without pretending to a calibrated CI.
  const spread = Math.min(0.45, 0.5 / Math.sqrt(observations + 1))
  const lo = Math.max(0, mastery - spread)
  const hi = Math.min(1, mastery + spread)

  return (
    <div>
      <div className="h-1.5 bg-rule relative">
        {thin && (
          <div
            className="absolute inset-y-0 bg-rule border-x border-faint/40"
            style={{ left: `${lo * 100}%`, width: `${(hi - lo) * 100}%` }}
          />
        )}
        <div
          className={`${color} ${thin ? 'opacity-50' : ''}`}
          style={{ width: `${mastery * 100}%`, position: 'absolute', inset: '0 auto 0 0' }}
        />
      </div>
      <p className="font-mono text-[10px] text-faint mt-1.5">
        {thin ? (
          <>
            <span className="text-amber">provisional</span> &middot; {observations}{' '}
            observation{observations === 1 ? '' : 's'}
          </>
        ) : (
          <>mastery {mastery.toFixed(2)} &middot; {observations} observations</>
        )}
      </p>
    </div>
  )
}