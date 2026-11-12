import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PageHead from '@/components/dashboard/PageHead'
import Simulator from '@/components/dashboard/Simulator'
import EmptyState from '@/components/dashboard/EmptyState'
import { buildSubjects } from '@/lib/simulator'
import { type Embed, one } from '@/lib/supabase/embed'

export default async function SimulatePage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('weekly_minutes, target_exam_id, exam_profiles:target_exam_id ( name )')
    .eq('student_id', user.id)
    .single()

  const examId = profile?.target_exam_id ?? null

  const [{ data: concepts }, { data: subjects }, { data: mastery }, { data: weights }] =
    await Promise.all([
      supabase.from('concepts').select('concept_id, subject_id'),
      supabase.from('subjects').select('subject_id, name').order('name'),
      supabase.from('mastery').select('concept_id, mastery_prob').eq('student_id', user.id),
      examId
        ? supabase.from('exam_topic_weights').select('concept_id, weight').eq('exam_id', examId)
        : Promise.resolve({ data: [] as { concept_id: string; weight: number }[] }),
    ])

  const lede =
    'Move hours between subjects and watch the projected readiness move. It starts from your own mastery estimates, weighted by your target exam, and gains saturate, so the answer is not linear.'

  if (!mastery || mastery.length === 0) {
    return (
      <main className="px-6 lg:px-10 py-8 pb-20">
        <PageHead eyebrow="SIMULATE" title="Spend the hours before you spend them." lede={lede} />
        <div className="max-w-lg">
          <EmptyState
            title="Nothing to simulate yet"
            body="The simulator projects from your mastery estimates, and those start with your first answers."
          />
        </div>
      </main>
    )
  }

  const examName = one(profile?.exam_profiles as Embed<{ name: string }>)?.name ?? null
  const budget = Math.max(1, Math.round((profile?.weekly_minutes ?? 300) / 60))

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead eyebrow="SIMULATE" title="Spend the hours before you spend them." lede={lede} />
      <Simulator
        subjects={buildSubjects({
          concepts: concepts ?? [],
          subjects: subjects ?? [],
          mastery,
          examWeights: weights ?? [],
        })}
        budget={budget}
        examName={examName}
      />
    </main>
  )
}
