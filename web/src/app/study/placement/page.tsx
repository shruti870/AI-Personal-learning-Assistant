import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PlacementRunner from '@/components/study/PlacementRunner'

type PoolItem = {
  difficulty: number
  concepts: { subject_id: string } | null
}

/** Even coverage across subjects, then across easy/medium/hard within each. */
function stratifiedSample<T extends PoolItem>(pool: T[], want: number): T[] {
  const bySubject = new Map<string, T[]>()
  for (const q of pool) {
    const key = q.concepts?.subject_id ?? 'unknown'
    const list = bySubject.get(key) ?? []
    list.push(q)
    bySubject.set(key, list)
  }

  const subjects = [...bySubject.keys()]
  const perSubject = Math.max(1, Math.floor(want / Math.max(1, subjects.length)))
  const picked: T[] = []

  for (const subject of subjects) {
    const items = bySubject.get(subject)!
    const bands: T[][] = [[], [], []]
    for (const q of items) {
      const d = Number(q.difficulty)
      bands[d < -0.3 ? 0 : d < 0.4 ? 1 : 2].push(q)
    }
    for (const band of bands) {
      const take = Math.ceil(perSubject / 3)
      picked.push(...shuffle(band).slice(0, take))
    }
  }

  // Top up from whatever is left if the strata came up short.
  const chosen = new Set(picked)
  const rest = shuffle(pool.filter((q) => !chosen.has(q)))
  while (picked.length < want && rest.length) picked.push(rest.pop()!)

  return shuffle(picked).slice(0, want)
}

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export default async function PlacementPage() {
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

  // Stratified sample, not the 20 easiest.
  //
  // Ordering by difficulty and taking the first 20 served an identical test
  // every sitting: the same questions, the same failures, the same diagnosis,
  // and entire subjects never sampled at all. This draws across subjects and
  // difficulty bands, and reshuffles on every attempt.
  const { data: pool } = await supabase
    .from('questions')
    .select(`
      question_id, stem, difficulty, median_time_sec, primary_concept_id,
      concepts:primary_concept_id ( name, subject_id ),
      options ( option_id, body, ordinal )
    `)
    .eq('is_active', true)
    .limit(400)

  const questions = pool ? stratifiedSample(pool, 20) : []

  if (questions.length === 0) {
    return (
      <main className="min-h-screen flex items-center justify-center px-6">
        <div className="max-w-md">
          <p className="font-mono text-[11px] eyebrow text-alarm mb-4">NO QUESTIONS</p>
          <h1 className="font-display font-extrabold text-2xl tight">
            The content bank is empty.
          </h1>
          <p className="mt-4 text-soft leading-relaxed">
            Run <span className="font-mono text-xs">002_seed_starter_content.sql</span> in
            the Supabase SQL editor, then reload.
          </p>
        </div>
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