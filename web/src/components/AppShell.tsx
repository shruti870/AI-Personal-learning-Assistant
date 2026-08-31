import { createClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'
import SideRail from '@/components/dashboard/SideRail'
import LogoutButton from '@/components/LogoutButton'

/**
 * One shell for every signed-in page, so the rail is always present and
 * there is never a screen you cannot navigate out of.
 */
export default async function AppShell({ children }: { children: React.ReactNode }) {
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

  const name = profile?.display_name ?? user.email?.split('@')[0] ?? 'Student'

  return (
    <div className="min-h-screen">
      <SideRail name={name} />
      <div className="lg:pl-56">
        <header className="border-b border-rule bg-paper/90 backdrop-blur sticky top-0 z-30">
          <div className="px-6 lg:px-10 h-14 flex items-center justify-between">
            <p className="font-mono text-[10px] eyebrow text-faint">
              {new Date().toLocaleDateString('en-IN', {
                weekday: 'long',
                day: 'numeric',
                month: 'short',
              })}
            </p>
            <LogoutButton />
          </div>
        </header>
        {children}
      </div>
    </div>
  )
}