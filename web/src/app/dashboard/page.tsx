import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'

import DiagnosisBanner from '@/components/dashboard/DiagnosisBanner'
import StatStrip from '@/components/dashboard/StatStrip'
import MasteryBySubject from '@/components/dashboard/MasteryBySubject'
import FixFirstQueue from '@/components/dashboard/FixFirstQueue'
import EmptyState from '@/components/dashboard/EmptyState'
import MasteryBar from '@/components/dashboard/MasteryBar'
import { getAnalytics } from '@/lib/analytics'

export default async function DashboardPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('display_name')
    .eq('student_id', user.id)
    .single()

  const a = await getAnalytics(user.id)
  const name = profile?.display_name ?? 'Student'

  if (a.attemptCount === 0) {
    return (
      <main className="px-6 lg:px-10 py-8 pb-20">
        <p className="font-mono text-[11px] eyebrow text-faint mb-4">TODAY</p>
        <h1 className="font-display font-extrabold text-3xl tight leading-tight">
          Nothing recorded yet, {name.split(' ')[0]}.
        </h1>
        <p className="mt-3 text-soft leading-relaxed max-w-lg">
          Everything here is computed from your own answers. There is no sample mode
          and no placeholder data, so the dashboard stays empty until you start.
        </p>
        <div className="mt-9 max-w-lg">
          <EmptyState
            title="Twenty questions, twelve minutes"
            body="Declare confidence before each answer. What comes back is a map of what you believe and how firmly, not a score."
          />
        </div>
      </main>
    )
  }

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <div className="flex flex-wrap items-center justify-between gap-4 mb-7">
        <div>
          <p className="font-mono text-[11px] eyebrow text-faint mb-2">TODAY</p>
          <p className="font-mono text-xs text-soft">
            Computed from {a.attemptCount} of your own attempts
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link
            href="/study"
            className="font-mono text-xs border border-ink px-5 py-2.5 hover:bg-ink hover:text-paper transition-colors"
          >
            Study
          </Link>
          <Link
            href="/study/placement"
            className="font-mono text-xs bg-ink text-paper px-5 py-2.5 hover:bg-blueprint transition-colors"
          >
            Take a test
          </Link>
        </div>
      </div>

      <div className="grid xl:grid-cols-12 gap-7">
        <div className="xl:col-span-8 space-y-7">
          <DiagnosisBanner
            name={name}
            rootCause={a.rootCause}
            confidentlyWrong={a.diagnosis.sureWrong}
          />
          <StatStrip
            attemptCount={a.attemptCount}
            focusHalfLife={a.focusHalfLife}
            sessionsTracked={a.sessionsTracked}
            activeMinutes={a.activeMinutes}
            namedBeliefs={a.fixFirst.length}
          />

          {a.thinEstimate && (
            <div className="border-l-2 border-amber bg-amber-wash px-5 py-4">
              <p className="font-mono text-[10px] eyebrow text-amber mb-2">
                ESTIMATES ARE PROVISIONAL
              </p>
              <p className="text-xs text-soft leading-relaxed">
                Median {a.medianObservations} observation
                {a.medianObservations === 1 ? '' : 's'} per concept. At this depth a
                mastery number is close to &ldquo;did you get that one question
                right&rdquo; and will swing on the next answer. It settles from about
                four attempts per concept.
              </p>
            </div>
          )}

          <section>
            <p className="font-mono text-[11px] eyebrow text-faint mb-5">WEAKEST RIGHT NOW</p>
            {a.weakest.length === 0 ? (
              <EmptyState
                title="No mastery estimates yet"
                body="These appear as soon as attempts are recorded against a concept."
              />
            ) : (
              <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-px bg-rule border border-rule">
                {a.weakest.map((w) => (
                  <Link
                    key={w.conceptId}
                    href={`/study/session?concept=${encodeURIComponent(w.conceptId)}`}
                    className="bg-card px-5 py-5 hover:bg-paper transition-colors"
                  >
                    <p className="font-mono text-[10px] text-faint mb-2">
                      {w.subjectId.toUpperCase()}
                    </p>
                    <p className="font-mono text-sm">{w.name}</p>
                    <div className="mt-3">
                      <MasteryBar mastery={w.mastery} observations={w.observations} />
                    </div>
                  </Link>
                ))}
              </div>
            )}
          </section>
        </div>

        <div className="xl:col-span-4 space-y-7">
          <FixFirstQueue items={a.fixFirst} />
          <MasteryBySubject subjects={a.subjects} />

          <div className="border-l-2 border-blueprint bg-blue-wash px-5 py-4">
            <p className="font-mono text-[10px] eyebrow text-blueprint mb-2">
              NOT YET COMPUTED
            </p>
            <p className="text-xs text-soft leading-relaxed">
              Forgetting curves, focus half-life, and the generated timetable need the
              Python fitter and about five tracked sessions. Nothing here is
              placeholder &mdash; those panels stay empty until the numbers are real.
            </p>
          </div>
        </div>
      </div>
    </main>
  )
}