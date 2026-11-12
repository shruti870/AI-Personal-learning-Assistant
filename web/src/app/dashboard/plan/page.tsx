import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import PageHead from '@/components/dashboard/PageHead'
import { getAnalytics } from '@/lib/analytics'
import RecomputeButton from '@/components/dashboard/RecomputeButton'
import PlanItemToggle from '@/components/dashboard/PlanItemToggle'

type Reason = {
  kind?: string
  effective_mastery?: number
  raw_mastery?: number
  blame_share?: number
  urgency?: number
  readiness?: number
  exam_weight?: number
  block_minutes_from?: string
}

type Item = {
  plan_item_id: string
  concept_id: string
  scheduled_for: string | null
  block_index: number | null
  allocated_minutes: number
  completed_at: string | null
  reason: Reason | null
  concepts: { name: string; subject_id: string } | { name: string; subject_id: string }[] | null
}

/** One plain sentence from the planner's numbers. */
function why(r: Reason | null): string {
  if (!r) return ''
  const bits: string[] = []
  if (r.kind === 'REVIEW') bits.push('you knew this, but it has started to fade')
  else if (r.effective_mastery !== undefined)
    bits.push(`mastery is ${Math.round(r.effective_mastery * 100)}%`)
  if ((r.blame_share ?? 0) >= 0.2)
    bits.push(`it explains ${Math.round((r.blame_share ?? 0) * 100)}% of your recent mistakes downstream`)
  if ((r.exam_weight ?? 1) > 1.05) bits.push('your target exam weights it heavily')
  return bits.length ? bits.join('; ') + '.' : ''
}

function dayLabel(iso: string | null): string {
  if (!iso) return 'UNSCHEDULED'
  return new Date(iso + 'T00:00:00')
    .toLocaleDateString('en-IN', { weekday: 'short', day: 'numeric', month: 'short' })
    .toUpperCase()
}

export default async function PlanPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: plan } = await supabase
    .from('study_plans')
    .select('plan_id, generated_at, plan_items ( plan_item_id, concept_id, scheduled_for, block_index, allocated_minutes, completed_at, reason, concepts:concept_id ( name, subject_id ) )')
    .eq('student_id', user.id)
    .eq('is_current', true)
    .order('generated_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  const a = await getAnalytics(user.id)

  if (!plan) {
    return (
      <main className="px-6 lg:px-10 py-8 pb-20">
        <PageHead
          eyebrow="PLAN"
          title="No plan generated yet."
          lede="The scheduler needs three things: your mastery estimates, a fitted forgetting curve, and a measured focus half-life. You have the first."
        />

        <div className="grid md:grid-cols-3 gap-px bg-rule border border-rule max-w-3xl">
          {[
            ['MASTERY ESTIMATES', a.attemptCount > 0 ? 'READY' : 'MISSING',
             `${a.attemptCount} attempts recorded`, a.attemptCount > 0],
            ['FORGETTING CURVE', 'MISSING',
             'Needs the Python fitter and repeat reviews', false],
            a.focusHalfLife !== null
              ? ['FOCUS HALF-LIFE', 'READY', `${a.focusHalfLife} minutes`, true]
              : ['FOCUS HALF-LIFE', 'MISSING',
                 `Needs 5 tracked sessions (${a.sessionsTracked} so far)`, false],
          ].map(([label, status, note, ok]) => (
            <div key={String(label)} className="bg-card px-5 py-5">
              <p className="font-mono text-[10px] eyebrow text-faint mb-3">{label}</p>
              <p
                className={`font-mono text-sm ${ok ? 'text-mastery' : 'text-faint'}`}
              >
                {status}
              </p>
              <p className="text-xs text-soft mt-2 leading-relaxed">{note}</p>
            </div>
          ))}
        </div>

        <p className="text-soft mt-8 max-w-lg leading-relaxed">
          Until then, work from the weakest concepts on your dashboard. Those are
          computed from real data and are already correctly ordered by the graph.
        </p>

        <div className="mt-6 flex flex-wrap items-start gap-4">
          <Link
            href="/study"
            className="inline-block font-mono text-sm border border-ink px-6 py-3 hover:bg-ink hover:text-paper transition-colors"
          >
            Go to study
          </Link>
          {a.attemptCount > 0 && <RecomputeButton label="Try generating a plan" />}
        </div>
      </main>
    )
  }

  const items = ((plan.plan_items ?? []) as unknown as Item[]).sort(
    (x, y) =>
      (x.scheduled_for ?? '').localeCompare(y.scheduled_for ?? '') ||
      (x.block_index ?? 0) - (y.block_index ?? 0)
  )
  const days = [...new Set(items.map((it) => it.scheduled_for))]
  const done = items.filter((it) => it.completed_at).length
  const minutes = items.reduce((t, it) => t + it.allocated_minutes, 0)

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="PLAN"
        title="Your current week."
        lede={`Generated ${new Date(plan.generated_at).toLocaleString('en-IN')}. ${items.length} blocks, ${minutes} minutes, ${done} done.`}
        aside={<RecomputeButton label="Regenerate plan" />}
      />
      <div className="space-y-8 max-w-3xl">
        {days.map((d) => (
          <section key={d ?? 'none'}>
            <p className="font-mono text-[11px] eyebrow text-faint mb-3">{dayLabel(d)}</p>
            <div className="space-y-3">
              {items
                .filter((it) => it.scheduled_for === d)
                .map((it) => {
                  const c = Array.isArray(it.concepts) ? it.concepts[0] : it.concepts
                  const reason = why(it.reason)
                  return (
                    <div key={it.plan_item_id} className="paper-card pl-7 pr-5 py-4">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div className="min-w-0">
                          <p className="font-mono text-[10px] text-faint mb-1.5">
                            {c?.subject_id?.toUpperCase()}
                            {it.reason?.kind ? ` · ${it.reason.kind}` : ''}
                          </p>
                          <Link
                            href={`/study/session?concept=${encodeURIComponent(it.concept_id)}`}
                            className={`font-display font-semibold text-base tight hover:text-blueprint ${
                              it.completed_at ? 'line-through text-faint' : ''
                            }`}
                          >
                            {c?.name ?? it.concept_id}
                          </Link>
                          {reason && (
                            <p className="text-xs text-soft mt-2 leading-relaxed">Why: {reason}</p>
                          )}
                        </div>
                        <div className="flex items-center gap-3 shrink-0">
                          <span className="font-mono text-[10px] text-amber">
                            {it.allocated_minutes} MIN
                          </span>
                          <PlanItemToggle itemId={it.plan_item_id} completedAt={it.completed_at} />
                        </div>
                      </div>
                    </div>
                  )
                })}
            </div>
          </section>
        ))}
      </div>
    </main>
  )
}
