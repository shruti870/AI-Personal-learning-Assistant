const stages = [
  {
    index: '01 / RECORD',
    title: 'Every answer, in detail',
    body: 'Which distractor you chose, the confidence you declared before answering, your response time against the median, and a one-line explanation of your reasoning.',
  },
  {
    index: '02 / DIAGNOSE',
    title: 'Named misconceptions',
    body: 'Wrong options map to specific false beliefs, not just to topics. Failures then propagate down the prerequisite graph until they reach something you genuinely don\u2019t know.',
  },
  {
    index: '03 / SCHEDULE',
    title: 'Two curves, one plan',
    body: 'How fast you forget each concept, and how long you can hold attention in one sitting. Your timetable is the intersection of both.',
  },
  {
    index: '04 / ADAPT',
    title: 'Re-fit continuously',
    body: 'Every attempt updates the model. Blocks that stop producing learning get cut short rather than ground through.',
  },
]

export default function Pipeline() {
  return (
    <section id="how" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <p className="font-mono text-[11px] eyebrow text-faint mb-12">THE PIPELINE</p>
        <div className="grid md:grid-cols-4 gap-px bg-rule border border-rule">
          {stages.map((s) => (
            <div key={s.index} className="bg-paper p-7">
              <p className="font-mono text-xs text-blueprint mb-4">{s.index}</p>
              <h3 className="font-display font-semibold text-lg mb-3 tight">{s.title}</h3>
              <p className="text-sm text-soft leading-relaxed">{s.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}