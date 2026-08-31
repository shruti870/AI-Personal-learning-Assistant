'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

const WINDOW_MS = 120_000      // full aggregation window
const FIRST_WINDOW_MS = 45_000 // shorter first window so a baseline exists fast
const LIVE_MS = 1_500          // how often the on-screen readout refreshes
const MIN_CHARS = 20           // below this a window is too sparse to mean anything
const PAUSE_MS = 2_000         // gap that counts as a pause
const IKI_CAP_MS = 10_000      // gaps above this are pauses, not typing rhythm
const BURST_GAP_MS = 1_000     // gap that breaks an uninterrupted run
const EXIT_KEYS = 10           // keystrokes examined after a pause

export type WindowMetrics = {
  charsTyped: number
  meanIkiMs: number | null
  sdIkiMs: number | null
  backspaceRate: number
  pausesOver2s: number
  longestPauseMs: number
  meanBurstLen: number | null
  pausesThinking: number
  pausesLost: number
}

/**
 * Derives a focus signal from typing rhythm.
 *
 * Deliberately does NOT claim to detect drowsiness. It measures deviation
 * from the student's own baseline within the session, which is measurable;
 * "sleepy vs thinking hard" is not separable from keystrokes alone.
 *
 * Pauses are classified by how they END rather than how long they run: a
 * thinking pause resolves into a confident burst, a disengaged one resolves
 * into corrections.
 */
export function useTypingTelemetry(opts: {
  sessionId: string | null
  enabled: boolean
}) {
  const supabase = createClient()

  const keyTimes = useRef<number[]>([])
  const backspaces = useRef(0)
  const chars = useRef(0)
  const pauses = useRef<number[]>([])
  const pendingPause = useRef<{ at: number; corrections: number; keys: number } | null>(null)
  const thinking = useRef(0)
  const lost = useRef(0)
  const runAttempts = useRef(0)
  const runFailures = useRef(0)
  const windowStart = useRef(Date.now())

  const [baseline, setBaseline] = useState<WindowMetrics | null>(null)
  const [current, setCurrent] = useState<WindowMetrics | null>(null)
  const [focusIndex, setFocusIndex] = useState<number | null>(null)
  const [windowCount, setWindowCount] = useState(0)
  // Live, unflushed view of the window in progress. Purely for display, so
  // the student sees something within seconds instead of after two minutes.
  const [live, setLive] = useState<WindowMetrics | null>(null)
  const [liveFocus, setLiveFocus] = useState<number | null>(null)
  const [windowProgress, setWindowProgress] = useState(0)

  const compute = useCallback((): WindowMetrics => {
    const t = keyTimes.current
    const ikis: number[] = []
    const bursts: number[] = []
    let burst = 1

    for (let i = 1; i < t.length; i++) {
      const gap = t[i] - t[i - 1]
      if (gap <= IKI_CAP_MS) ikis.push(gap)
      if (gap <= BURST_GAP_MS) {
        burst++
      } else {
        bursts.push(burst)
        burst = 1
      }
    }
    bursts.push(burst)

    const mean = ikis.length ? ikis.reduce((a, b) => a + b, 0) / ikis.length : null
    const sd =
      mean !== null && ikis.length > 1
        ? Math.sqrt(ikis.reduce((a, g) => a + (g - mean) ** 2, 0) / (ikis.length - 1))
        : null

    return {
      charsTyped: chars.current,
      meanIkiMs: mean,
      sdIkiMs: sd,
      backspaceRate: chars.current ? backspaces.current / chars.current : 0,
      pausesOver2s: pauses.current.length,
      longestPauseMs: pauses.current.length ? Math.max(...pauses.current) : 0,
      meanBurstLen: bursts.length ? bursts.reduce((a, b) => a + b, 0) / bursts.length : null,
      pausesThinking: thinking.current,
      pausesLost: lost.current,
    }
  }, [])

  /** Higher is better. 1.0 means "typing like your session baseline". */
  const scoreAgainst = useCallback((m: WindowMetrics, base: WindowMetrics) => {
    const parts: number[] = []
    if (m.meanIkiMs && base.meanIkiMs) parts.push(base.meanIkiMs / m.meanIkiMs)
    if (m.sdIkiMs && base.sdIkiMs) parts.push(base.sdIkiMs / m.sdIkiMs)
    if (base.backspaceRate > 0.01) {
      parts.push(base.backspaceRate / Math.max(m.backspaceRate, 0.001))
    }
    if (m.meanBurstLen && base.meanBurstLen) parts.push(m.meanBurstLen / base.meanBurstLen)
    if (!parts.length) return null
    const raw = parts.reduce((a, b) => a + b, 0) / parts.length
    return Math.max(0, Math.min(1.6, raw))
  }, [])

  const flush = useCallback(async () => {
    if (!opts.enabled || chars.current < MIN_CHARS) return

    const m = compute()
    const minutesIn = (Date.now() - windowStart.current) / 60000

    setCurrent(m)
    setWindowCount((n) => n + 1)

    if (!baseline) {
      setBaseline(m)
      setFocusIndex(1)
    } else {
      setFocusIndex(scoreAgainst(m, baseline))
    }

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (user) {
      await supabase.from('typing_windows').insert({
        session_id: opts.sessionId,
        student_id: user.id,
        minutes_into_session: Number(minutesIn.toFixed(2)),
        window_seconds: Math.round(WINDOW_MS / 1000),
        chars_typed: m.charsTyped,
        mean_iki_ms: m.meanIkiMs,
        sd_iki_ms: m.sdIkiMs,
        backspace_rate: m.backspaceRate,
        pauses_over_2s: m.pausesOver2s,
        longest_pause_ms: m.longestPauseMs,
        mean_burst_len: m.meanBurstLen,
        pauses_thinking: m.pausesThinking,
        pauses_lost: m.pausesLost,
        run_attempts: runAttempts.current,
        run_failures: runFailures.current,
      })
    }

    keyTimes.current = []
    backspaces.current = 0
    chars.current = 0
    pauses.current = []
    thinking.current = 0
    lost.current = 0
    runAttempts.current = 0
    runFailures.current = 0
    windowStart.current = Date.now()
  }, [opts.enabled, opts.sessionId, baseline, compute, scoreAgainst, supabase])

  // Flush completed windows. The first is short so a baseline exists early.
  useEffect(() => {
    if (!opts.enabled) return
    const ms = baseline ? WINDOW_MS : FIRST_WINDOW_MS
    const t = setInterval(flush, ms)
    return () => clearInterval(t)
  }, [opts.enabled, baseline, flush])

  // Live readout, refreshed every couple of seconds.
  useEffect(() => {
    if (!opts.enabled) return
    const t = setInterval(() => {
      const target = baseline ? WINDOW_MS : FIRST_WINDOW_MS
      setWindowProgress(
        Math.min(1, (Date.now() - windowStart.current) / target)
      )
      if (chars.current < 5) {
        setLive(null)
        setLiveFocus(null)
        return
      }
      const m = compute()
      setLive(m)
      setLiveFocus(baseline ? scoreAgainst(m, baseline) : null)
    }, LIVE_MS)
    return () => clearInterval(t)
  }, [opts.enabled, baseline, compute, scoreAgainst])

  const onKeyDown = useCallback(
    (e: { key: string }) => {
      if (!opts.enabled) return
      const now = Date.now()
      const last = keyTimes.current[keyTimes.current.length - 1]

      if (last && now - last > PAUSE_MS) {
        pauses.current.push(now - last)
        pendingPause.current = { at: now, corrections: 0, keys: 0 }
      }

      if (pendingPause.current) {
        const p = pendingPause.current
        p.keys++
        if (e.key === 'Backspace' || e.key === 'Delete') p.corrections++
        if (p.keys >= EXIT_KEYS) {
          // A pause that resolves into corrections is disengagement.
          // One that resolves into clean typing was thought.
          if (p.corrections / p.keys > 0.25) lost.current++
          else thinking.current++
          pendingPause.current = null
        }
      }

      keyTimes.current.push(now)
      if (e.key === 'Backspace' || e.key === 'Delete') backspaces.current++
      else if (e.key.length === 1) chars.current++
    },
    [opts.enabled]
  )

  const noteRun = useCallback((passed: boolean) => {
    runAttempts.current++
    if (!passed) runFailures.current++
  }, [])

  return {
    onKeyDown,
    noteRun,
    flush,
    focusIndex,
    current,
    baseline,
    windowCount,
    hasBaseline: baseline !== null,
    // live view of the in-progress window
    live,
    liveFocus,
    windowProgress,
    charsThisWindow: chars.current,
    minChars: MIN_CHARS,
  }
}