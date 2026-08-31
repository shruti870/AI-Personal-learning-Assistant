import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import CodeRunner from '@/components/study/CodeRunner'

export default async function CodePage() {
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

  const { data: problems } = await supabase
    .from('coding_problems')
    .select('problem_id, title, prompt, starter_code, difficulty, concept_id, language_label, coding_tests ( test_id, input_json, expect_json, is_hidden, ordinal ), problem_starters ( language, label, starter_code, is_runnable )')
    .eq('is_active', true)
    .order('difficulty', { ascending: true })

  if (!problems || problems.length === 0) {
    return (
      <main className="px-6 lg:px-10 py-16">
        <p className="font-mono text-[11px] eyebrow text-alarm mb-4">NO PROBLEMS</p>
        <h1 className="font-display font-extrabold text-2xl tight">
          Run migrations 003, 004 and 005 first.
        </h1>
        <p className="mt-4 text-soft max-w-md leading-relaxed">
          Migration 003 creates the telemetry tables, 004 adds the problems, and 005 adds the per-language starter code.
        </p>
      </main>
    )
  }

  return (
    <CodeRunner
      problems={JSON.parse(JSON.stringify(problems))}
      trackingOptIn={profile?.tracking_opt_in ?? false}
    />
  )
}