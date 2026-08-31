import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PageHead from '@/components/dashboard/PageHead'
import ConceptMap from '@/components/dashboard/ConceptMap'

export default async function MapPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const [{ data: concepts }, { data: prereqs }, { data: mastery }, { data: subjects }] =
    await Promise.all([
      supabase.from('concepts').select('concept_id, name, subject_id, level'),
      supabase.from('prerequisites').select('parent_id, child_id, weight'),
      supabase
        .from('mastery')
        .select('concept_id, mastery_prob, observation_count')
        .eq('student_id', user.id),
      supabase.from('subjects').select('subject_id, name'),
    ])

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="CONCEPT MAP"
        title="Everything you know, and what it rests on."
        lede="Node colour is your current mastery. Grey means unobserved. Edges run from prerequisite upward to dependent."
      />
      <ConceptMap
        concepts={concepts ?? []}
        prereqs={prereqs ?? []}
        mastery={mastery ?? []}
        subjects={subjects ?? []}
      />
    </main>
  )
}