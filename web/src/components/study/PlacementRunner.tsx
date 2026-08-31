'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { useStudySession } from '@/hooks/useStudySession'

type Opt = { option_id: string; body: string; ordinal: number }
type Q = {
  question_id: string
  stem: string
  difficulty: number
  median_time_sec: number
  primary_concept_id: string
  concepts: { name: string; subject_id: string } | null
  options: Opt[]
}

type Result = {
  isCorrect: boolean
  errorType: string
  misconception: { label: string; remediation_note: string } | null
  correctAnswer: string | null
  concept: string | null
}

const CONF = [
  { v: 1, label: 'Not sure' },
  { v: 2, label: 'Fairly sure' },
  { v: 3, label: 'Certain' },
]

export default function PlacementRunner({
  questions,
  trackingOptIn,
}: {
  questions: Q[]
  trackingOptIn: boolean
}) {
  const router = useRouter()
  const [consented, setConsented] = useState(trackingOptIn)
  const [started, setStarted] = useState(false)

  const [i, setI] = useState(0)
  const [conf, setConf] = useState<number | null>(null)
  const [picked, setPicked] = useState<string | null>(null)
  const [result, setResult] = useState<Result | null>(null)
  const [busy, setBusy] = useState(false)
  const [shownAt, setShownAt] = useState(Date.now())
  const [log, setLog] = useState<{ correct: boolean; type: string }[]>([])
  const [done, setDone] = useState(false)

  const session = useStudySession({
    plannedMinutes: 12,
    enabled: started && consented,
  })

  const q = questions[i]
  const sorted = useMemo(
    () => (q ? [...q.options].sort((a, b) => a.ordinal - b.ordinal) : []),
    [q]
  )

  useEffect(() => {
    setShownAt(Date.now())
  }, [i])

  async function submit(optionId: string) {
    if (!conf || busy) return
    setBusy(true)
    setPicked(optionId)

    const res = await fetch('/api/attempt', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        questionId: q.question_id,
        optionId,
        confidence: conf,
        timeTakenSec: (Date.now() - shownAt) / 1000,
        sessionId: session.sessionId,
        minutesIntoSession:
          session.activeMinutes === null
            ? null
            : Number(session.activeMinutes.toFixed(2)),
      }),
    })

    const data: Result = await res.json()
    setResult(data)
    setLog((l) => [...l, { correct: data.isCorrect, type: data.errorType }])
    setBusy(false)
  }

  async function next() {
    if (i + 1 >= questions.length) {
      const first5 = log.slice(0, 5)
      const baseline = first5.length
        ? first5.filter((x) => x.correct).length / first5.length
        : undefined
      await session.endSession('completed', baseline)
      setDone(true)
      router.refresh()
      return
    }
    setI(i + 1)
    setConf(null)
    setPicked(null)
    setResult(null)
  }

  // ---------- Consent gate ----------
  if (!started) {
    return (
      <main className="min-h-screen flex items-center px-6 py-16">
        <div className="mx-auto max-w-2xl w-full">
          <p className="font-mono text-[11px] eyebrow text-blueprint mb-5">
            PLACEMENT TEST
          </p>
          <h1 className="font-display font-extrabold text-4xl tight leading-[1.1]">
            Twenty questions.<br />No score at the end.
          </h1>
          <p className="mt-6 text-soft leading-relaxed max-w-lg">
            Declare confidence before each answer. What comes back is a map of what
            you believe and how firmly, plus the concepts underneath your errors.
          </p>

          <div className="mt-10 border border-rule bg-card">
            <div className="border-b border-rule px-6 py-3">
              <p className="font-mono text-[10px] eyebrow text-faint">
                ATTENTION TRACKING &mdash; OPTIONAL
              </p>
            </div>
            <div className="px-6 py-6">
              <p className="text-sm text-soft leading-relaxed mb-5">
                If you turn this on, we record when the tab loses focus, gaps of 45
                seconds or more without input, and how long each answer takes. That is
                what measures your focus half-life and sizes your study blocks. We do
                not record keystrokes or which other tabs are open.
              </p>
              <button
                onClick={() => setConsented(!consented)}
                role="switch"
                aria-checked={consented}
                className={`font-mono text-xs px-4 py-2.5 border transition-colors ${
                  consented
                    ? 'border-blueprint bg-blueprint text-paper'
                    : 'border-rule text-soft hover:border-ink hover:text-ink'
                }`}
              >
                {consented ? 'TRACKING ON' : 'TRACKING OFF'}
              </button>
            </div>
          </div>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <button
              onClick={() => setStarted(true)}
              className="font-mono text-sm bg-ink text-paper px-8 py-4 hover:bg-blueprint transition-colors"
            >
              Begin
            </button>
            <Link href="/dashboard" className="font-mono text-xs text-faint hover:text-ink">
              Not now
            </Link>
          </div>
        </div>
      </main>
    )
  }

  // ---------- Completion ----------
  if (done) {
    const correct = log.filter((l) => l.correct).length
    const confWrong = log.filter((l) => l.type === 'misconception').length
    const guesses = log.filter((l) => l.type === 'guess').length

    return (
      <main className="min-h-screen flex items-center px-6 py-16">
        <div className="mx-auto max-w-2xl w-full">
          <p className="font-mono text-[11px] eyebrow text-blueprint mb-5">COMPLETE</p>
          <h1 className="font-display font-extrabold text-4xl tight leading-[1.1]">
            Mapped onto the graph.
          </h1>
          <p className="mt-6 text-soft leading-relaxed">
            {correct} of {log.length} correct &mdash; but that is the least useful number
            here. {confWrong} answers traced to a named misconception, and {guesses} correct
            answers came back too fast to credit.
          </p>
          <p className="font-mono text-xs text-faint mt-6">
            {session.tracking
              ? `Active time ${(session.activeMinutes ?? 0).toFixed(1)} min \u00b7 ${session.blurCount} tab switches`
              : 'Attention tracking was off for this session.'}
          </p>
          <Link
            href="/dashboard"
            className="inline-block mt-9 font-mono text-sm bg-ink text-paper px-8 py-4 hover:bg-blueprint transition-colors"
          >
            See your diagnosis
          </Link>
        </div>
      </main>
    )
  }

  // ---------- Question ----------
  return (
    <main className="min-h-screen px-6 py-10">
      <div className="mx-auto max-w-2xl">
        <div className="flex items-center justify-between gap-4 mb-8">
          <span className="font-mono text-[10px] eyebrow text-faint">
            {i + 1} / {questions.length}
          </span>
          <div className="flex-1 h-px bg-rule relative">
            <div
              className="absolute inset-y-0 left-0 bg-ink"
              style={{ width: `${(i / questions.length) * 100}%` }}
            />
          </div>
          {consented && (
            <span className="font-mono text-[10px] text-faint">
              {(session.activeMinutes ?? 0).toFixed(1)}m active
            </span>
          )}
        </div>

        <p className="font-mono text-[10px] eyebrow text-faint mb-4">
          {q.concepts?.subject_id?.toUpperCase()} &middot; {q.concepts?.name}
        </p>
        <p className="text-xl leading-relaxed mb-9">{q.stem}</p>

        <p className="font-mono text-[10px] eyebrow text-faint mb-3">
          HOW SURE ARE YOU?
        </p>
        <div className="flex flex-wrap gap-2 mb-9">
          {CONF.map((c) => (
            <button
              key={c.v}
              onClick={() => setConf(c.v)}
              disabled={!!result}
              className={`font-mono text-xs px-4 py-2.5 border transition-colors disabled:opacity-60 ${
                conf === c.v
                  ? 'border-ink bg-ink text-paper'
                  : 'border-rule text-soft hover:border-ink hover:text-ink'
              }`}
            >
              {c.label}
            </button>
          ))}
        </div>

        <div className="space-y-2">
          {sorted.map((o) => {
            const chosen = picked === o.option_id
            const isRight = result && o.body === result.correctAnswer
            return (
              <button
                key={o.option_id}
                onClick={() => submit(o.option_id)}
                disabled={!conf || !!result}
                className={`w-full text-left px-5 py-4 border transition-colors disabled:cursor-not-allowed ${
                  chosen && result && !result.isCorrect
                    ? 'border-alarm bg-alarm-wash'
                    : isRight
                    ? 'border-mastery bg-card'
                    : 'border-rule hover:border-ink disabled:hover:border-rule'
                } ${!conf ? 'opacity-50' : ''}`}
              >
                <span className="text-sm">{o.body}</span>
              </button>
            )
          })}
        </div>

        {!conf && (
          <p className="font-mono text-[10px] text-faint mt-4">
            Pick a confidence level first.
          </p>
        )}

        {result && (
          <div className="mt-8 border-t border-rule pt-6">
            <span
              className={`font-mono text-[10px] eyebrow px-2.5 py-1 ${
                result.errorType === 'misconception'
                  ? 'bg-alarm text-paper'
                  : result.errorType === 'mastered'
                  ? 'bg-mastery text-paper'
                  : 'bg-ink text-paper'
              }`}
            >
              {result.errorType.replace('_', ' ').toUpperCase()}
            </span>

            {result.misconception && (
              <div className="border-l-2 border-amber pl-4 mt-5">
                <p className="font-mono text-[10px] eyebrow text-faint mb-1.5">
                  NAMED BELIEF
                </p>
                <p className="text-sm">{result.misconception.label}</p>
                <p className="text-sm text-soft mt-2 leading-relaxed">
                  {result.misconception.remediation_note}
                </p>
              </div>
            )}

            <button
              onClick={next}
              className="mt-7 font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors"
            >
              {i + 1 >= questions.length ? 'Finish' : 'Next question'}
            </button>
          </div>
        )}
      </div>
    </main>
  )
}