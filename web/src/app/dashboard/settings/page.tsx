import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import PageHead from '@/components/dashboard/PageHead'
import SettingsForm from '@/components/dashboard/SettingsForm'

export default async function SettingsPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('display_name, weekly_minutes, tracking_opt_in, target_exam_id')
    .eq('student_id', user.id)
    .single()

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <PageHead
        eyebrow="SETTINGS"
        title="What we track, and what we do with it."
        lede="Attention tracking is off unless you turn it on. Without it the planner falls back to fixed 25-minute blocks instead of blocks sized to you."
      />
      <SettingsForm
        email={user.email ?? ''}
        displayName={profile?.display_name ?? ''}
        weeklyMinutes={profile?.weekly_minutes ?? 300}
        trackingOptIn={profile?.tracking_opt_in ?? false}
        targetExamId={profile?.target_exam_id ?? null}
      />
    </main>
  )
}