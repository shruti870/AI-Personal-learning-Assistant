const stats = [
  { label: 'CONCEPTS', value: '480' },
  { label: 'EDGES', value: '790' },
  { label: 'SUBJECTS', value: '8' },
]

export default function ConceptGraph() {
  return (
    <section className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-14 items-center">
          <div className="md:col-span-6 order-2 md:order-1">
            <div className="stack relative h-64 mx-auto max-w-sm" aria-hidden="true">
              <div className="layer l1 absolute inset-0 border border-rule bg-card flex items-center justify-center">
                <span className="font-mono text-[10px] eyebrow text-faint">LEVEL 0 â€” FOUNDATIONS</span>
              </div>
              <div className="layer l2 absolute inset-0 border border-blueprint/40 bg-blue-wash translate-x-4 translate-y-4 flex items-center justify-center">
                <span className="font-mono text-[10px] eyebrow text-blueprint">LEVEL 3 â€” STRUCTURES</span>
              </div>
              <div className="layer l3 absolute inset-0 border-2 border-amber bg-amber-wash translate-x-8 translate-y-8 flex items-center justify-center">
                <span className="font-mono text-[10px] eyebrow text-amber">LEVEL 6 â€” ADVANCED</span>
              </div>
            </div>
          </div>

          <div className="md:col-span-6 order-1 md:order-2">
            <p className="font-mono text-[11px] eyebrow text-faint mb-6">CONCEPT GRAPH</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
              Nothing is scheduled<br />before its prerequisites.
            </h2>
            <p className="mt-6 text-soft leading-relaxed">
              Every subject is a directed graph, not a list of chapters. The engine walks it downward
              to diagnose and upward to plan, so you&rsquo;re never handed a topic that depends on
              something you haven&rsquo;t got yet.
            </p>
            <div className="mt-8 grid grid-cols-3 gap-6 font-mono text-xs">
              {stats.map((s) => (
                <div key={s.label}>
                  <p className="text-faint">{s.label}</p>
                  <p className="text-ink text-2xl mt-1">{s.value}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}