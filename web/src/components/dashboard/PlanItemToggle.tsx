'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

/** Marks a plan block done. RLS (own_plan_items) limits this to the owner. */
export default function PlanItemToggle({
  itemId,
  completedAt,
}: {
  itemId: string
  completedAt: string | null
}) {
  const router = useRouter()
  const [done, setDone] = useState(Boolean(completedAt))
  const [busy, setBusy] = useState(false)
  const [failed, setFailed] = useState(false)

  async function toggle() {
    setBusy(true)
    const next = !done
    const { error } = await createClient()
      .from('plan_items')
      .update({ completed_at: next ? new Date().toISOString() : null })
      .eq('plan_item_id', itemId)
    setFailed(Boolean(error))
    if (!error) {
      setDone(next)
      // The strike-through and the "N done" count are rendered by the server page.
      router.refresh()
    }
    setBusy(false)
  }

  return (
    <span className="inline-flex items-center gap-2">
      {failed && <span className="font-mono text-[10px] text-alarm">NOT SAVED</span>}
      <button
        onClick={toggle}
        disabled={busy}
        aria-pressed={done}
        className={`font-mono text-[10px] px-3 py-1.5 border transition-colors disabled:opacity-50 ${
          done
            ? 'border-mastery text-mastery'
            : 'border-rule text-soft hover:border-ink hover:text-ink'
        }`}
      >
        {done ? '✓ DONE' : 'MARK DONE'}
      </button>
    </span>
  )
}
