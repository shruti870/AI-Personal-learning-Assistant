const cells = [
  {
    label: 'SURE + CORRECT',
    title: 'Mastered',
    note: 'Scheduled for review, not practice.',
    bg: 'bg-card',
    labelColor: 'text-faint',
    titleColor: 'text-mastery',
    noteColor: 'text-soft',
  },
  {
    label: 'SURE + WRONG',
    title: 'Fix this first',
    note: 'A belief, not a slip. Highest priority.',
    bg: 'bg-alarm-wash',
    labelColor: 'text-alarm',
    titleColor: 'text-alarm',
    noteColor: 'text-alarm/80',
  },
  {
    label: 'UNSURE + CORRECT',
    title: 'Probably guessed',
    note: 'Credited less. Re-tested sooner.',
    bg: 'bg-card',
    labelColor: 'text-faint',
    titleColor: 'text-ink',
    noteColor: 'text-soft',
  },
  {
    label: 'UNSURE + WRONG',
    title: 'Known gap',
    note: 'You already knew. Straightforward to close.',
    bg: 'bg-card',
    labelColor: 'text-faint',
    titleColor: 'text-ink',
    noteColor: 'text-soft',
  },
]

export default function DiagnosisGrid() {
  return (
    <section className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-12">
          <div className="md:col-span-5">
            <p className="font-mono text-[11px] eyebrow text-faint mb-6">CONFIDENCE &times; CORRECTNESS</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
              Right and wrong<br />is two states.<br />This is four.
            </h2>
            <p className="mt-6 text-soft leading-relaxed">
              You declare confidence before you answer. That one extra tap separates a lucky guess
              from real mastery &mdash; and finds the beliefs you hold firmly and wrongly, which are
              the most expensive thing in your head.
            </p>
          </div>

          <div className="md:col-span-7 grid grid-cols-2 gap-px bg-rule border border-rule">
            {cells.map((c) => (
              <div key={c.label} className={`${c.bg} p-6 min-h-[150px] flex flex-col justify-between`}>
                <p className={`font-mono text-[10px] eyebrow ${c.labelColor}`}>{c.label}</p>
                <div>
                  <p className={`font-display font-semibold text-lg ${c.titleColor}`}>{c.title}</p>
                  <p className={`text-sm mt-1 ${c.noteColor}`}>{c.note}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}