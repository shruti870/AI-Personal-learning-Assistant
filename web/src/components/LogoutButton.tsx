'use client'

import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export default function LogoutButton() {
  const router = useRouter()
  const supabase = createClient()

  async function logout() {
    await supabase.auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <button
      onClick={logout}
      className="font-mono text-xs border border-ink px-4 py-2 hover:bg-ink hover:text-paper transition-colors"
    >
      Log out
    </button>
  )
}