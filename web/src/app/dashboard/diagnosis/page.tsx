import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PageHead from '@/components/dashboard/PageHead'
import EmptyState from '@/components/dashboard/EmptyState'
import { getAnalytics } from '@/lib/analytics'

const LABELS: Record<string, string> = {
  misconception: 'Misconception',
  procedural_slip: 'Procedural slip',
  careless: 'Careless',
  guess: 'Guess',
  uncertain_correct: 'Uncertain correct',
  mastered: 'Mastered',
}

const TONE: Record<string, string> = {
  misconception: 'bg-alarm',
  procedural_slip: 'bg-amber',
  careless: 'bg-blueprint',
  guess: 'bg-faint',
}

export default async function DiagnosisPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const a = await getAnalytics(user.id)
  const d = a.diagnosis

  if (d.total === 0) {
    return (
      <main className="px-6 lg:px-10 py-8 pb-20">
        <PageHead
          eyebrow="DIAGNOSIS"
          title="Nothing to diagnose yet."
          lede="This page reads your own attempts. Answer some questions and it fills in."
        />
        <div className="max-w-lg">
          <EmptyState
            title="Start with the placement test"
            body="Twenty questions across the concept graph, with confidence declared before each answer."
          />
        </div>
      </main>
    )
  }

  const cells = [
    { label: 'SURE + WRONG', n: d.sureWrong, title: 'Confidently wrong', note: 'Held beliefs, not slips. Highest priority.', bg: 'bg-alarm-wash', accent: 'text-alarm' },
    { label: 'UNSURE + WRONG', n: d.unsureWrong, title: 'Known gaps', note: 'You already suspected these.', bg: 'bg-card', accent: 'text-ink' },
    { label: 'UNSURE + CORRECT', n: d.unsureCorrect, title: 'Probably guessed', note: 'Credited at reduced weight.', bg: 'bg-card', accent: 'text-ink' },
    { label: 'SURE + CORRECT', n: d.sureCorrect, title: 'Mastered', note: 'Moved to review.', bg: 'bg-card', accent: 'text-mastery' },
  ]

  const wrongTotal = d.errorMix.reduce((x, e) => x + e.n, 0)
  const misconceptions = d.errorMix.find((e) => e.kind === 'misconception')?.n ?? 0

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="DIAGNOSIS"
        title="What you believe, and how firmly."
        lede={`${d.total} attempts recorded. Correctness alone would tell you ${d.sureCorrect + d.unsureCorrect} out of ${d.total}. This is the rest of it.`}
      />

      <div className="grid xl:grid-cols-12 gap-7">
        <div className="xl:col-span-7 space-y-7">
          <section>
            <p className="font-mono text-[11px] eyebrow text-faint mb-5">
              CONFIDENCE &times; CORRECTNESS
            </p>
            <div className="grid sm:grid-cols-2 gap-px bg-rule border border-rule">
              {cells.map((c) => (
                <div key={c.label} className={`${c.bg} px-6 py-6`}>
                  <div className="flex items-start justify-between gap-3 mb-4">
                    <p className={`font-mono text-[10px] eyebrow ${c.accent}`}>{c.label}</p>
                    <span className={`font-display font-extrabold text-2xl tight ${c.accent}`}>
                      {c.n}
                    </span>
                  </div>
                  <p className={`font-display font-semibold text-lg tight ${c.accent}`}>
                    {c.title}
                  </p>
                  <p className="text-sm text-soft mt-1.5 leading-relaxed">{c.note}</p>
                </div>
              ))}
            </div>
          </section>

          {wrongTotal > 0 && (
            <section className="border border-rule bg-card">
              <div className="border-b border-rule px-6 py-3">
                <p className="font-mono text-[10px] eyebrow text-faint">
                  HOW THE WRONG ANSWERS WENT WRONG
                </p>
              </div>
              <div className="px-6 py-6">
                <div className="flex h-3 border border-rule mb-5">
                  {d.errorMix.map((e) => (
                    <div
                      key={e.kind}
                      className={TONE[e.kind] ?? 'bg-faint'}
                      style={{ width: `${(e.n / wrongTotal) * 100}%` }}
                      title={`${LABELS[e.kind] ?? e.kind}: ${e.n}`}
                    />
                  ))}
                </div>
                <dl className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                  {d.errorMix.map((e) => (
                    <div key={e.kind}>
                      <div className="flex items-center gap-2 mb-1">
                        <span className={`w-2 h-2 ${TONE[e.kind] ?? 'bg-faint'}`} />
                        <dt className="font-mono text-[10px] text-faint">
                          {LABELS[e.kind] ?? e.kind}
                        </dt>
                      </div>
                      <dd className="font-mono text-sm">{e.n}</dd>
                    </div>
                  ))}
                </dl>
                {misconceptions > 0 && (
                  <p className="text-sm text-soft mt-6 leading-relaxed">
                    {misconceptions} of your {wrongTotal} wrong answers map to a named
                    misconception rather than a slip. Those are the ones re-teaching fixes
                    and more practice does not.
                  </p>
                )}
              </div>
            </section>
          )}
        </div>

        <div className="xl:col-span-5">
          <section className="border border-rule bg-card">
            <div className="border-b border-rule px-5 py-3">
              <p className="font-mono text-[10px] eyebrow text-faint">NAMED BELIEFS</p>
            </div>
            {a.fixFirst.length === 0 ? (
              <div className="px-5 py-5">
                <p className="text-xs text-soft leading-relaxed">
                  None diagnosed yet. A belief is named when a wrong answer matches a
                  distractor tagged to a specific misconception.
                </p>
              </div>
            ) : (
              <ol className="divide-y divide-rule">
                {a.fixFirst.map((f, i) => (
                  <li key={f.belief} className="px-5 py-4">
                    <div className="flex items-baseline justify-between gap-3 mb-1.5">
                      <span className="font-mono text-[11px]">
                        <span className="text-faint mr-2">
                          {String(i + 1).padStart(2, '0')}
                        </span>
                        {f.concept}
                      </span>
                      <span className="font-mono text-[10px] text-amber">{f.times}x</span>
                    </div>
                    <p className="text-xs text-soft leading-relaxed">{f.belief}</p>
                  </li>
                ))}
              </ol>
            )}
          </section>
        </div>
      </div>
    </main>
  )
}