'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

const IDLE_MS = 45_000

/**
 * Owns the attention data for one study session.
 *
 * activeMinutes = wall clock MINUS time the tab was hidden MINUS idle gaps.
 * Everything downstream (the focus curve, block sizing, the fatigue cutoff)
 * is fitted against this number, so it must not be elapsed time.
 */
export function useStudySession(opts: {
  subjectId?: string
  plannedMinutes?: number
  enabled: boolean
}) {
  const supabase = createClient()
  const [sessionId, setSessionId] = useState<string | null>(null)
  const [activeMinutes, setActiveMinutes] = useState(0)

  const startedAt = useRef<number>(Date.now())
  const deadMs = useRef(0)          // hidden + idle time, accumulated
  const hiddenAt = useRef<number | null>(null)
  const idleAt = useRef<number | null>(null)
  const lastInput = useRef<number>(Date.now())
  const blurCount = useRef(0)
  const idleSeconds = useRef(0)
  const sessionRef = useRef<string | null>(null)

  const logEvent = useCallback(
    async (type: string, durationMs?: number) => {
      if (!sessionRef.current || !opts.enabled) return
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return
      await supabase.from('focus_events').insert({
        session_id: sessionRef.current,
        student_id: user.id,
        event_type: type,
        duration_ms: durationMs ?? null,
      })
    },
    [supabase, opts.enabled]
  )

  // Open the session. Skipped entirely when tracking is off, so no
  // half-populated session rows are written.
  useEffect(() => {
    if (!opts.enabled) return
    let cancelled = false
    ;(async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user || cancelled) return

      const { data } = await supabase
        .from('study_sessions')
        .insert({
          student_id: user.id,
          subject_id: opts.subjectId ?? null,
          planned_minutes: opts.plannedMinutes ?? null,
        })
        .select('session_id')
        .single()

      if (data && !cancelled) {
        sessionRef.current = data.session_id
        setSessionId(data.session_id)
      }
    })()
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opts.enabled])

  // Tick active minutes once a second. Guarded on `enabled`: without the
  // input listeners there is nothing to clear an idle gap, so an unguarded
  // timer would freeze active time at exactly IDLE_MS and write that same
  // value onto every attempt.
  useEffect(() => {
    if (!opts.enabled) return
    const t = setInterval(() => {
      const now = Date.now()

      // Roll idle into dead time as it accrues
      if (!idleAt.current && now - lastInput.current > IDLE_MS && !hiddenAt.current) {
        idleAt.current = lastInput.current + IDLE_MS
        logEvent('idle_start')
      }

      let dead = deadMs.current
      if (hiddenAt.current) dead += now - hiddenAt.current
      if (idleAt.current) dead += now - idleAt.current

      setActiveMinutes(Math.max(0, (now - startedAt.current - dead) / 60000))
    }, 1000)
    return () => clearInterval(t)
  }, [opts.enabled, logEvent])

  // Visibility and input listeners
  useEffect(() => {
    if (!opts.enabled) return

    const onVisibility = () => {
      if (document.visibilityState === 'hidden') {
        hiddenAt.current = Date.now()
        blurCount.current += 1
        logEvent('tab_blur')
      } else if (hiddenAt.current) {
        const d = Date.now() - hiddenAt.current
        deadMs.current += d
        hiddenAt.current = null
        lastInput.current = Date.now()
        logEvent('tab_focus', d)
      }
    }

    const onInput = () => {
      const now = Date.now()
      if (idleAt.current) {
        const d = now - idleAt.current
        deadMs.current += d
        idleSeconds.current += Math.round(d / 1000)
        idleAt.current = null
        logEvent('idle_end', d)
      }
      lastInput.current = now
    }

    document.addEventListener('visibilitychange', onVisibility)
    for (const e of ['mousemove', 'keydown', 'scroll', 'click', 'touchstart']) {
      window.addEventListener(e, onInput, { passive: true })
    }
    return () => {
      document.removeEventListener('visibilitychange', onVisibility)
      for (const e of ['mousemove', 'keydown', 'scroll', 'click', 'touchstart']) {
        window.removeEventListener(e, onInput)
      }
    }
  }, [opts.enabled, logEvent])

  const endSession = useCallback(
    async (reason: string, baselineAccuracy?: number) => {
      if (!sessionRef.current) return
      await supabase
        .from('study_sessions')
        .update({
          ended_at: new Date().toISOString(),
          active_minutes: Number(activeMinutes.toFixed(2)),
          blur_count: blurCount.current,
          idle_seconds: idleSeconds.current,
          baseline_accuracy: baselineAccuracy ?? null,
          end_reason: reason,
        })
        .eq('session_id', sessionRef.current)
    },
    [supabase, activeMinutes]
  )

  return {
    sessionId,
    // null when tracking is off, so callers write NULL rather than a
    // meaningless constant into attempts.minutes_into_session.
    activeMinutes: opts.enabled ? activeMinutes : null,
    tracking: opts.enabled,
    blurCount: blurCount.current,
    endSession,
  }
}