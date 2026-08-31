export default function StatStrip({
  attemptCount,
  focusHalfLife,
  sessionsTracked,
  activeMinutes,
  namedBeliefs,
}: {
  attemptCount: number
  focusHalfLife: number | null
  sessionsTracked: number
  activeMinutes: number
  namedBeliefs: number
}) {
  const stats = [
    {
      label: 'ATTEMPTS RECORDED',
      value: String(attemptCount),
      note: `${activeMinutes.toFixed(0)} tracked active minutes`,
      tone: 'text-ink',
    },
    {
      label: 'NAMED BELIEFS OPEN',
      value: String(namedBeliefs),
      note: namedBeliefs ? 'Wrong answers with a diagnosed cause' : 'No tagged misconceptions yet',
      tone: namedBeliefs ? 'text-amber' : 'text-faint',
    },
    {
      label: 'FOCUS HALF-LIFE',
      value: focusHalfLife ? `${focusHalfLife}m` : '--',
      note: focusHalfLife
        ? 'Blocks sized to match'
        : sessionsTracked < 5
        ? `Needs 5 tracked sessions (${sessionsTracked} so far)`
        : 'Curve not yet separable from noise; using the default block length',
      tone: focusHalfLife ? 'text-blueprint' : 'text-faint',
    },
  ]

  return (
    <div className="grid sm:grid-cols-3 gap-px bg-rule border border-rule">
      {stats.map((s) => (
        <div key={s.label} className="bg-card px-6 py-5">
          <p className="font-mono text-[10px] eyebrow text-faint mb-3">{s.label}</p>
          <p className={`font-display font-extrabold text-3xl tight ${s.tone}`}>{s.value}</p>
          <p className="text-xs text-soft mt-2 leading-relaxed">{s.note}</p>
        </div>
      ))}
    </div>
  )
}