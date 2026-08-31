import type { SubjectMastery } from '@/lib/analytics'

export default function MasteryBySubject({ subjects }: { subjects: SubjectMastery[] }) {
  return (
    <div className="border border-rule bg-card">
      <div className="border-b border-rule px-5 py-3">
        <p className="font-mono text-[10px] eyebrow text-faint">MASTERY BY SUBJECT</p>
      </div>
      <div className="px-5 py-5 space-y-4">
        {subjects.length === 0 && (
          <p className="text-xs text-soft leading-relaxed">
            Nothing observed yet. Mastery appears once you answer questions in a subject.
          </p>
        )}
        {subjects.map((s) => (
          <div key={s.subjectId}>
            <div className="flex items-baseline justify-between gap-3 mb-1.5">
              <span className="font-mono text-[11px] truncate">{s.subject}</span>
              <span className="font-mono text-[10px] text-faint shrink-0">
                {s.mastery.toFixed(2)}
              </span>
            </div>
            <div className="h-1.5 bg-rule relative">
              <div
                className={
                  s.mastery < 0.5 ? 'bg-alarm' : s.mastery < 0.7 ? 'bg-amber' : 'bg-mastery'
                }
                style={{ width: `${s.mastery * 100}%`, position: 'absolute', inset: '0 auto 0 0' }}
              />
            </div>
            <p className="font-mono text-[10px] text-faint mt-1.5">
              {s.observed} of {s.concepts} concepts observed
            </p>
          </div>
        ))}
      </div>
    </div>
  )
}