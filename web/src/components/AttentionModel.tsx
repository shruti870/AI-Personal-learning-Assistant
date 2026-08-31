const blocks = [
  {
    when: '09:10 \u2014 09:32 \u00b7 NEW MATERIAL',
    title: 'Sorting basics',
    why: 'Root cause of 6 Dijkstra failures. Placed early, attention is highest.',
    minutes: '22 MIN',
    tilt: '-rotate-[0.4deg]',
  },
  {
    when: '09:37 \u2014 09:59 \u00b7 CONTRAST DRILL',
    title: 'BFS vs DFS ordering',
    why: 'You\u2019ve confused these four times. Interleaved, not blocked.',
    minutes: '22 MIN',
    tilt: 'rotate-[0.3deg]',
  },
  {
    when: '21:15 \u2014 21:27 \u00b7 REVIEW',
    title: 'Normalization \u2014 3NF',
    why: 'Retention drops below 0.75 tomorrow. Night slot: review, not new learning.',
    minutes: '12 MIN',
    tilt: '-rotate-[0.2deg]',
  },
]

export default function AttentionModel() {
  return (
    <section id="focus" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-14 items-start">
          <div className="md:col-span-5">
            <p className="font-mono text-[11px] eyebrow text-faint mb-6">ATTENTION MODEL</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
              Your focus half-life<br />is 23 minutes.
            </h2>
            <p className="mt-6 text-soft leading-relaxed">
              Measured from tab switches, idle gaps, response-time drift, and the point where your
              accuracy starts falling inside a session. Nobody&rsquo;s attention is 60 minutes long
              just because the timetable says so.
            </p>

            <div className="mt-9 border border-rule bg-card p-6">
              <p className="font-mono text-[10px] eyebrow text-faint mb-4">ACCURACY WITHIN A SESSION</p>
              <svg
                viewBox="0 0 300 110"
                className="w-full"
                role="img"
                aria-label="Accuracy decaying over minutes into a session, with a cutoff marked at 23 minutes."
              >
                <line x1="26" y1="92" x2="290" y2="92" stroke="#C8D2C7" />
                <line x1="26" y1="8" x2="26" y2="92" stroke="#C8D2C7" />
                <path d="M26 22 C 90 26, 130 44, 170 62 S 240 88, 290 96" fill="none" stroke="#1B4D8F" strokeWidth="2" />
                <line x1="152" y1="8" x2="152" y2="92" stroke="#B8721A" strokeWidth="1" strokeDasharray="3 3" />
                <text x="158" y="18" fontFamily="var(--font-plex-mono)" fontSize="9" fill="#B8721A">23 min &mdash; cutoff</text>
                <text x="26" y="106" fontFamily="var(--font-plex-mono)" fontSize="9" fill="#7C877F">0</text>
                <text x="270" y="106" fontFamily="var(--font-plex-mono)" fontSize="9" fill="#7C877F">45 min</text>
              </svg>
            </div>
          </div>

          <div className="md:col-span-7">
            <p className="font-mono text-[10px] eyebrow text-faint mb-6">TUESDAY &mdash; GENERATED FROM YOUR CURVE</p>
            <div className="space-y-4">
              {blocks.map((b) => (
                <div key={b.title} className={`paper-card pl-7 pr-6 py-5 ${b.tilt}`}>
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <p className="font-mono text-[10px] text-faint mb-1.5">{b.when}</p>
                      <p className="font-display font-semibold text-lg tight">{b.title}</p>
                      <p className="text-sm text-soft mt-1">{b.why}</p>
                    </div>
                    <span className="font-mono text-[10px] text-amber whitespace-nowrap">{b.minutes}</span>
                  </div>
                </div>
              ))}
            </div>
            <p className="font-mono text-[11px] text-faint mt-6">
              Every block links to the trace that produced it.
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}