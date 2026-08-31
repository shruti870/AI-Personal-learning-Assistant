// NOTE: these section weights are placeholders for layout only.
// Replace with real weights from actual papers before showing this publicly.
const targets = [
  {
    name: 'TCS NQT',
    split: ['Aptitude 40% \u00b7 Verbal 20%', 'Programming logic 25% \u00b7 DBMS 15%'],
  },
  {
    name: 'Infosys SE',
    split: ['Reasoning 35% \u00b7 Aptitude 30%', 'Pseudocode 25% \u00b7 Verbal 10%'],
  },
  {
    name: 'Amazon SDE-1',
    split: ['DSA 60% \u00b7 System design 15%', 'OS 15% \u00b7 DBMS 10%'],
  },
  {
    name: 'Semester exams',
    split: ['Weighted by your syllabus', 'and time to the exam date'],
  },
]

export default function ExamTargets() {
  return (
    <section id="exams" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="flex flex-wrap items-end justify-between gap-6 mb-10">
          <div>
            <p className="font-mono text-[11px] eyebrow text-faint mb-5">PLACEMENT MODE</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight max-w-xl">
              Same engine.<br />Different weights.
            </h2>
          </div>
          <p className="text-soft max-w-md leading-relaxed">
            Pick a target and every topic gets reweighted by how much that company actually tests it.
            Your semester prep and your placement prep stop competing for the same hours.
          </p>
        </div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-px bg-rule border border-rule">
          {targets.map((t) => (
            <div key={t.name} className="bg-paper p-6">
              <p className="font-display font-semibold text-lg tight mb-3">{t.name}</p>
              <p className="font-mono text-xs text-soft leading-relaxed">
                {t.split[0]}
                <br />
                {t.split[1]}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}