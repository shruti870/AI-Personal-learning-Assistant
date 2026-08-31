import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import PlacementRunner from '@/components/study/PlacementRunner'

export default async function SessionPage({
  searchParams,
}: {
  searchParams: Promise<{ concept?: string; minutes?: string }>
}) {
  const params = await searchParams
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('tracking_opt_in')
    .eq('student_id', user.id)
    .single()

  // Roughly one question per 90 seconds of block time.
  const minutes = Number(params.minutes ?? 22)
  const want = Math.max(5, Math.min(20, Math.round((minutes * 60) / 90)))

  let query = supabase
    .from('questions')
    .select(`
      question_id, stem, difficulty, median_time_sec, primary_concept_id,
      concepts:primary_concept_id ( name, subject_id ),
      options ( option_id, body, ordinal )
    `)
    .eq('is_active', true)
    .limit(Math.max(want * 3, 30))

  if (params.concept) {
    query = query.eq('primary_concept_id', params.concept)
  }

  const { data: rows } = await query

  // Shuffle so repeat drills on the same concept are not identical.
  const questions = rows
    ? [...rows].sort(() => Math.random() - 0.5).slice(0, want)
    : []

  if (questions.length === 0) {
    return (
      <main className="px-6 lg:px-10 py-16">
        <p className="font-mono text-[11px] eyebrow text-amber mb-4">NOTHING TO SERVE</p>
        <h1 className="font-display font-extrabold text-2xl tight max-w-lg">
          No questions authored for this concept yet.
        </h1>
        <p className="mt-4 text-soft max-w-md leading-relaxed">
          The starter bank covers 16 concepts. Everything else is waiting on the
          content track.
        </p>
        <Link
          href="/study"
          className="inline-block mt-8 font-mono text-sm border border-ink px-6 py-3 hover:bg-ink hover:text-paper transition-colors"
        >
          Back to study
        </Link>
      </main>
    )
  }

  return (
    <PlacementRunner
      questions={JSON.parse(JSON.stringify(questions))}
      trackingOptIn={profile?.tracking_opt_in ?? false}
    />
  )
}