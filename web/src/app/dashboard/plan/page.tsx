import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import PageHead from '@/components/dashboard/PageHead'
import { getAnalytics } from '@/lib/analytics'

export default async function PlanPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: plan } = await supabase
    .from('study_plans')
    .select('plan_id, generated_at, plan_items ( concept_id, scheduled_for, allocated_minutes, priority_score, reason )')
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
            ['FOCUS HALF-LIFE', 'MISSING',
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

        <Link
          href="/study"
          className="inline-block mt-6 font-mono text-sm border border-ink px-6 py-3 hover:bg-ink hover:text-paper transition-colors"
        >
          Go to study
        </Link>
      </main>
    )
  }

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="PLAN"
        title="Your current week."
        lede={`Generated ${new Date(plan.generated_at).toLocaleString('en-IN')}.`}
      />
      <div className="space-y-3 max-w-3xl">
        {(plan.plan_items ?? []).map((it, i) => (
          <div key={i} className="paper-card pl-7 pr-5 py-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="font-mono text-[10px] text-faint mb-1.5">
                  {it.scheduled_for}
                </p>
                <p className="font-display font-semibold text-base tight">
                  {it.concept_id}
                </p>
              </div>
              <span className="font-mono text-[10px] text-amber shrink-0">
                {it.allocated_minutes} MIN
              </span>
            </div>
          </div>
        ))}
      </div>
    </main>
  )
}