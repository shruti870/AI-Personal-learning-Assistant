import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import Link from 'next/link'
import MasteryBar from '@/components/dashboard/MasteryBar'

export default async function StudyHub() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  const { count: attempts } = await supabase
    .from('attempts')
    .select('*', { count: 'exact', head: true })
    .eq('student_id', user.id)

  const { data: weakest } = await supabase
    .from('mastery')
    .select('concept_id, mastery_prob, observation_count, concepts:concept_id ( name, subject_id )')
    .eq('student_id', user.id)
    .order('mastery_prob', { ascending: true })
    .limit(4)

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <p className="font-mono text-[11px] eyebrow text-faint mb-4">STUDY</p>
      <h1 className="font-display font-extrabold text-3xl tight leading-tight">
        Pick how you want to work.
      </h1>
      <p className="mt-3 text-soft leading-relaxed max-w-xl">
        {attempts
          ? `${attempts} attempts recorded so far.`
          : 'Nothing recorded yet. Start with the placement test.'}
      </p>

      <div className="grid md:grid-cols-3 gap-px bg-rule border border-rule mt-9">
        <Link href="/study/placement" className="bg-card px-6 py-7 hover:bg-paper transition-colors">
          <p className="font-mono text-[10px] eyebrow text-blueprint mb-4">DIAGNOSTIC</p>
          <p className="font-display font-semibold text-lg tight">Placement test</p>
          <p className="text-sm text-soft mt-2 leading-relaxed">
            Twenty questions across the graph. Re-take any time to re-estimate.
          </p>
          <p className="font-mono text-[10px] text-faint mt-4">~12 min</p>
        </Link>

        <Link href="/study/session" className="bg-card px-6 py-7 hover:bg-paper transition-colors">
          <p className="font-mono text-[10px] eyebrow text-amber mb-4">PRACTICE</p>
          <p className="font-display font-semibold text-lg tight">Concept drill</p>
          <p className="text-sm text-soft mt-2 leading-relaxed">
            Questions from one concept, in a short focused block.
          </p>
          <p className="font-mono text-[10px] text-faint mt-4">22 min block</p>
        </Link>

        <Link href="/study/code" className="bg-card px-6 py-7 hover:bg-paper transition-colors">
          <p className="font-mono text-[10px] eyebrow text-mastery mb-4">CODING</p>
          <p className="font-display font-semibold text-lg tight">Code practice</p>
          <p className="text-sm text-soft mt-2 leading-relaxed">
            Write and run solutions. Typing rhythm feeds the attention model.
          </p>
          <p className="font-mono text-[10px] text-faint mt-4">Open-ended</p>
        </Link>
      </div>

      {weakest && weakest.length > 0 && (
        <section className="mt-12">
          <p className="font-mono text-[11px] eyebrow text-faint mb-5">WEAKEST RIGHT NOW</p>
          <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-px bg-rule border border-rule">
            {weakest.map((w) => {
              const c = w.concepts as unknown as { name: string; subject_id: string } | null
              return (
                <Link
                  key={w.concept_id}
                  href={`/study/session?concept=${w.concept_id}`}
                  className="bg-card px-5 py-5 hover:bg-paper transition-colors"
                >
                  <p className="font-mono text-[10px] text-faint mb-2">
                    {c?.subject_id?.toUpperCase()}
                  </p>
                  <p className="font-mono text-sm">{c?.name ?? w.concept_id}</p>
                  <div className="mt-3">
                    <MasteryBar
                      mastery={Number(w.mastery_prob)}
                      observations={Number(w.observation_count ?? 0)}
                    />
                  </div>
                </Link>
              )
            })}
          </div>
        </section>
      )}
    </main>
  )
}