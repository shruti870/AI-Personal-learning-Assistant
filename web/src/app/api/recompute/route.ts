import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Asks the ML service to refit this student: mastery, focus half-life,
 * forgetting curve, then a fresh weekly plan (ml/main.py, _recompute).
 *
 * Runs server-side so ML_API_KEY never reaches the browser, and always for
 * the signed-in student, never an id from the request body.
 */
export const maxDuration = 120

export async function POST() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Not signed in' }, { status: 401 })

  const base = (process.env.ML_URL ?? 'http://localhost:8000').replace(/\/$/, '')

  let res: Response
  try {
    res = await fetch(`${base}/recompute/${user.id}`, {
      method: 'POST',
      headers: { 'X-API-Key': process.env.ML_API_KEY ?? '' },
      signal: AbortSignal.timeout(110_000),
      cache: 'no-store',
    })
  } catch {
    return NextResponse.json(
      { error: 'The analysis service is not reachable. Is it running (uvicorn main:app)?' },
      { status: 502 }
    )
  }

  const body = await res.json().catch(() => ({}))
  if (!res.ok) {
    return NextResponse.json(
      { error: body.detail ?? `Analysis service returned ${res.status}.` },
      { status: 502 }
    )
  }
  return NextResponse.json(body)
}
