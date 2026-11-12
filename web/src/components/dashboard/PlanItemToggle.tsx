'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

/** Marks a plan block done. RLS (own_plan_items) limits this to the owner. */
export default function PlanItemToggle({
  itemId,
  completedAt,
}: {
  itemId: string
  completedAt: string | null
}) {
  const [done, setDone] = useState(Boolean(completedAt))
  const [busy, setBusy] = useState(false)

  async function toggle() {
    setBusy(true)
    const next = !done
    const { error } = await createClient()
      .from('plan_items')
      .update({ completed_at: next ? new Date().toISOString() : null })
      .eq('plan_item_id', itemId)
    if (!error) setDone(next)
    setBusy(false)
  }

  return (
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
  )
}
