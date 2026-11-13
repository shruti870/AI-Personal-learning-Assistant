'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'

type Result = {
  status?: string
  plans?: number
  attention_profiles?: number
  half_life_rows?: number
  error?: string
}

function summarise(r: Result): string {
  if (r.error) return r.error
  if (r.status === 'no_attempts') return 'Nothing to analyse yet. Answer a few questions first.'
  const parts = [
    r.plans ? 'new plan generated' : 'not enough data for a plan yet',
    r.attention_profiles ? 'focus half-life fitted' : null,
    r.half_life_rows ? 'forgetting curve fitted' : null,
  ].filter(Boolean)
  return `Done: ${parts.join(', ')}.`
}

export default function RecomputeButton({ label = 'Refresh analysis' }: { label?: string }) {
  const router = useRouter()
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  async function run() {
    setBusy(true)
    setMessage(null)
    try {
      const res = await fetch('/api/recompute', { method: 'POST' })
      const data: Result = await res.json().catch(() => ({ error: `Failed (${res.status})` }))
      setMessage(summarise(data))
      if (res.ok) router.refresh()
    } catch {
      setMessage('Could not reach the server.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      <button
        onClick={run}
        disabled={busy}
        className="font-mono text-xs border border-ink px-5 py-2.5 hover:bg-ink hover:text-paper transition-colors disabled:opacity-50 disabled:pointer-events-none"
      >
        {busy ? 'Analysing… (up to a minute)' : label}
      </button>
      {message && (
        <p className="font-mono text-[11px] text-soft mt-3 max-w-md" role="status">
          {message}
        </p>
      )}
    </div>
  )
}
