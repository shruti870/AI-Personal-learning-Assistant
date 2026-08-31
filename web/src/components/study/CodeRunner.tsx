'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useStudySession } from '@/hooks/useStudySession'
import { useTypingTelemetry } from '@/hooks/useTypingTelemetry'
import {
  runRemote,
  runPython,
  loadPyodide,
  type TestCase,
  type TestResult,
} from '@/lib/runners'

type Starter = {
  language: string
  label: string
  starter_code: string
  is_runnable: boolean
}

type Problem = {
  problem_id: string
  title: string
  prompt: string
  starter_code: string
  difficulty: number
  concept_id: string | null
  language_label: string | null
  coding_tests: TestCase[]
  problem_starters: Starter[]
}

/** Older rows stored a literal backslash-n. Repair on read. */
function normalise(code: string) {
  return code.replace(/\\n/g, '\n').replace(/\\t/g, '  ')
}

function difficultyLabel(d: number) {
  if (d < -0.4) return 'EASY'
  if (d < 0.4) return 'MEDIUM'
  return 'HARD'
}

const FALLBACK_STARTERS: Record<string, string> = {
  cpp: 'int solve() {\n    // your code here\n}',
  java: 'static int solve() {\n    // your code here\n}',
  python: 'def solve():\n    # your code here\n    pass',
}

const EXT: Record<string, string> = { cpp: 'CPP', java: 'JAVA', python: 'PY' }

// Python runs in the browser. Everything else is compiled on the server.
const LOCAL_LANGS = new Set(['python'])

const ORDER = ['cpp', 'java', 'python']

export default function CodeRunner({
  problems,
  trackingOptIn,
}: {
  problems: Problem[]
  trackingOptIn: boolean
}) {
  const [pi, setPi] = useState(0)
  const problem = problems[pi]

  const starters = useMemo(() => {
    const list = [...(problem.problem_starters ?? [])].sort(
      (a, b) => ORDER.indexOf(a.language) - ORDER.indexOf(b.language)
    )
    if (list.length > 0) return list
    // Migration 005 not run: fall back to the single stored starter.
    return [
      {
        language: 'cpp',
        label: 'C++',
        starter_code: problem.starter_code,
        is_runnable: true,
      },
    ]
  }, [problem])

  const [lang, setLang] = useState(starters[0]?.language ?? 'cpp')

  const starterFor = (language: string) =>
    normalise(
      starters.find((s) => s.language === language)?.starter_code ??
        FALLBACK_STARTERS[language] ??
        ''
    )

  const [code, setCode] = useState(() => starterFor(lang))
  const [results, setResults] = useState<TestResult[] | null>(null)
  const [runError, setRunError] = useState<string | null>(null)
  const [running, setRunning] = useState(false)
  const [pyStatus, setPyStatus] = useState<'idle' | 'loading' | 'ready' | 'failed'>('idle')
  const taRef = useRef<HTMLTextAreaElement>(null)

  // Warm Pyodide as soon as Python is chosen, so Run is not the slow step.
  useEffect(() => {
    if (lang !== 'python' || pyStatus !== 'idle') return
    setPyStatus('loading')
    loadPyodide()
      .then(() => setPyStatus('ready'))
      .catch(() => setPyStatus('failed'))
  }, [lang, pyStatus])

  const session = useStudySession({ plannedMinutes: 25, enabled: trackingOptIn })
  const typing = useTypingTelemetry({
    sessionId: session.sessionId,
    enabled: trackingOptIn,
  })

  const lines = useMemo(() => code.split('\n').length, [code])

  function selectProblem(i: number) {
    const next = problems[i]
    const list = next.problem_starters ?? []
    const keep = list.some((s) => s.language === lang) ? lang : list[0]?.language ?? 'cpp'
    setPi(i)
    setLang(keep)
    setCode(
      normalise(
        list.find((s) => s.language === keep)?.starter_code ??
          next.starter_code ??
          FALLBACK_STARTERS[keep] ??
          ''
      )
    )
    setResults(null)
    setRunError(null)
  }

  function switchLanguage(next: string) {
    if (next === lang) return
    const untouched = code.trim() === starterFor(lang).trim()
    if (!untouched && !confirm('Switch language? Your current code will be replaced.')) {
      return
    }
    setLang(next)
    setCode(starterFor(next))
    setResults(null)
    setRunError(null)
  }

  async function run() {
    setRunning(true)
    setRunError(null)
    const outcome = LOCAL_LANGS.has(lang)
      ? await runPython(code, problem.coding_tests)
      : await runRemote(problem.problem_id, lang, code)
    setRunning(false)
    setResults(outcome.results)
    setRunError(outcome.error)
    typing.noteRun(!outcome.error && outcome.results.every((x) => x.passed))
  }

  const passed = results?.filter((r) => r.passed).length ?? 0
  const fi = typing.liveFocus ?? typing.focusIndex
  const live = typing.live

  return (
    <main className="px-6 lg:px-10 py-8 pb-20">
      <div className="flex flex-wrap items-end justify-between gap-4 mb-7">
        <div>
          <p className="font-mono text-[11px] eyebrow text-faint mb-3">
            CODE PRACTICE &middot; {difficultyLabel(problem.difficulty)}
          </p>
          <h1 className="font-display font-extrabold text-2xl tight">{problem.title}</h1>
        </div>
        <div className="flex gap-2">
          {problems.map((p, i) => (
            <button
              key={p.problem_id}
              onClick={() => selectProblem(i)}
              className={`font-mono text-[10px] px-3 py-2 border transition-colors ${
                i === pi
                  ? 'border-ink bg-ink text-paper'
                  : 'border-rule text-soft hover:border-ink hover:text-ink'
              }`}
            >
              {p.title}
            </button>
          ))}
        </div>
      </div>

      <div className="grid xl:grid-cols-12 gap-7">
        <div className="xl:col-span-8 space-y-5">
          <div className="border border-rule bg-card px-6 py-5">
            <p className="text-sm leading-relaxed">{problem.prompt}</p>
          </div>

          <div className="border border-rule bg-card">
            <div className="border-b border-rule px-4 py-2.5 flex flex-wrap items-center justify-between gap-3">
              <div className="flex items-center gap-3">
                <div className="flex gap-px bg-rule border border-rule">
                  {starters.map((st) => (
                    <button
                      key={st.language}
                      onClick={() => switchLanguage(st.language)}
                      className={`font-mono text-[10px] px-3 py-1.5 transition-colors ${
                        lang === st.language
                          ? 'bg-ink text-paper'
                          : 'bg-card text-soft hover:text-ink'
                      }`}
                    >
                      {st.label}
                    </button>
                  ))}
                </div>
                <span className="font-mono text-[10px] eyebrow text-faint">
                  SOLUTION.{EXT[lang] ?? 'TXT'} &middot; {lines} LINES
                </span>
              </div>
              <button
                onClick={run}
                disabled={running || (lang === 'python' && pyStatus === 'loading')}
                className="font-mono text-xs border border-ink px-4 py-1.5 hover:bg-ink hover:text-paper transition-colors disabled:opacity-50"
              >
                {running
                  ? 'Running...'
                  : lang === 'python' && pyStatus === 'loading'
                  ? 'Loading Python...'
                  : 'Run tests'}
              </button>
            </div>
            <textarea
              ref={taRef}
              value={code}
              onChange={(e) => setCode(e.target.value)}
              onKeyDown={typing.onKeyDown}
              spellCheck={false}
              rows={16}
              className="w-full bg-card font-mono text-sm px-4 py-4 resize-y focus:outline-none leading-relaxed"
              style={{ tabSize: 2 }}
            />
            <div className="border-t border-rule px-4 py-2.5">
              <p className="font-mono text-[10px] text-faint leading-relaxed">
                {lang === 'python' ? (
                  <>
                    Runs in your browser through Pyodide, so it works without a
                    connection once loaded. Define <span className="text-ink">solve</span>{' '}
                    and <span className="text-ink">return</span> the answer.{' '}
                    {pyStatus === 'loading' && 'Downloading the runtime, about 10 MB, once per visit.'}
                    {pyStatus === 'failed' && (
                      <span className="text-alarm">Runtime unreachable. Try C++ or Java.</span>
                    )}
                  </>
                ) : (
                  <>
                    Compiled and run on the server. Write only the{' '}
                    <span className="text-ink">solve</span> function &mdash; includes,{' '}
                    {lang === 'java' ? 'the class wrapper' : 'headers'} and main() are
                    generated for you. Needs a network connection.
                  </>
                )}
              </p>
            </div>
          </div>

          {(results || runError) && (
            <div className="border border-rule bg-card">
              <div className="border-b border-rule px-4 py-2.5 flex items-center justify-between">
                <span className="font-mono text-[10px] eyebrow text-faint">RESULTS</span>
                {results && (
                  <span
                    className={`font-mono text-[10px] ${
                      passed === results.length ? 'text-mastery' : 'text-alarm'
                    }`}
                  >
                    {passed} / {results.length} PASSED
                  </span>
                )}
              </div>
              <div className="px-4 py-4">
                {runError ? (
                  <p className="font-mono text-xs text-alarm">{runError}</p>
                ) : (
                  <ul className="space-y-2">
                    {results!.map((r) => (
                      <li key={r.ordinal} className="font-mono text-xs flex flex-wrap gap-3">
                        <span className={r.passed ? 'text-mastery' : 'text-alarm'}>
                          {r.passed ? 'PASS' : 'FAIL'}
                        </span>
                        <span className="text-faint">
                          {r.hidden ? 'hidden test' : `test ${r.ordinal + 1}`}
                        </span>
                        {!r.passed && !r.hidden && (
                          <span className="text-soft">
                            got {r.got} &middot; want {r.want}
                          </span>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          )}
        </div>

        <div className="xl:col-span-4 space-y-5">
          {!trackingOptIn ? (
            <div className="border-l-2 border-amber bg-amber-wash px-5 py-4">
              <p className="font-mono text-[10px] eyebrow text-amber mb-2">TRACKING OFF</p>
              <p className="text-xs text-soft leading-relaxed">
                Typing rhythm is not being recorded, so this session will not refine your
                focus model.{' '}
                <Link href="/dashboard/settings" className="text-ink border-b border-rule">
                  Turn it on
                </Link>
                .
              </p>
            </div>
          ) : (
            <>
              <div className="border border-rule bg-card">
                <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
                  <p className="font-mono text-[10px] eyebrow text-faint">FOCUS SIGNAL</p>
                  <span className="font-mono text-[10px] text-faint">
                    {typing.windowCount} window{typing.windowCount === 1 ? '' : 's'}
                  </span>
                </div>

                <div className="px-5 py-5">
                  {/* Window progress, so it is obvious something is happening */}
                  <div className="h-1 bg-rule relative mb-4">
                    <div
                      className="bg-blueprint absolute inset-y-0 left-0 transition-all duration-1000"
                      style={{ width: `${typing.windowProgress * 100}%` }}
                    />
                  </div>

                  {!typing.hasBaseline ? (
                    <>
                      <p className="font-display font-extrabold text-3xl tight text-faint">
                        {typing.charsThisWindow}
                        <span className="font-mono text-sm text-faint">
                          {' '}/ {typing.minChars} chars
                        </span>
                      </p>
                      <p className="text-xs text-soft mt-2 leading-relaxed">
                        Establishing your baseline. Keep typing &mdash; the first window
                        closes after 45 seconds and sets the reference everything else is
                        measured against.
                      </p>
                    </>
                  ) : (
                    <>
                      <p
                        className={`font-display font-extrabold text-3xl tight ${
                          (fi ?? 1) < 0.7
                            ? 'text-alarm'
                            : (fi ?? 1) < 0.9
                            ? 'text-amber'
                            : 'text-mastery'
                        }`}
                      >
                        {(fi ?? 1).toFixed(2)}
                      </p>
                      <p className="text-xs text-soft mt-2 leading-relaxed">
                        Relative to your own baseline this session. Not an absolute
                        measure, and not a claim about tiredness.
                      </p>
                      {(fi ?? 1) < 0.7 && (
                        <div className="border-l-2 border-alarm pl-4 mt-4">
                          <p className="text-xs text-alarm leading-relaxed">
                            Rhythm has drifted well below where you started. This is
                            usually the point to stop rather than push through.
                          </p>
                        </div>
                      )}
                    </>
                  )}
                </div>
              </div>

              {/* Live, unflushed metrics so there is feedback within seconds */}
              <div className="border border-rule bg-card">
                <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
                  <p className="font-mono text-[10px] eyebrow text-faint">LIVE</p>
                  {typing.liveFocus !== null && (
                    <span className="font-mono text-[10px] text-blueprint">
                      idx {typing.liveFocus.toFixed(2)}
                    </span>
                  )}
                </div>
                {!live ? (
                  <div className="px-5 py-5">
                    <p className="text-xs text-soft leading-relaxed">
                      Start typing in the editor. Metrics appear after a few keystrokes.
                    </p>
                  </div>
                ) : (
                  <dl className="divide-y divide-rule font-mono text-xs">
                    {[
                      ['chars this window', live.charsTyped],
                      ['mean gap', live.meanIkiMs ? `${Math.round(live.meanIkiMs)}ms` : '--'],
                      ['rhythm sd', live.sdIkiMs ? `${Math.round(live.sdIkiMs)}ms` : '--'],
                      ['backspace rate', live.backspaceRate.toFixed(3)],
                      ['burst length', live.meanBurstLen ? live.meanBurstLen.toFixed(1) : '--'],
                      ['pauses over 2s', live.pausesOver2s],
                      ['pauses: thinking', live.pausesThinking],
                      ['pauses: lost', live.pausesLost],
                    ].map(([k, v]) => (
                      <div key={String(k)} className="px-5 py-2.5 flex justify-between gap-3">
                        <dt className="text-faint">{k}</dt>
                        <dd>{v}</dd>
                      </div>
                    ))}
                  </dl>
                )}
                <div className="border-t border-rule px-5 py-3">
                  <p className="font-mono text-[10px] text-faint leading-relaxed">
                    Aggregates only. No keystrokes or code content are stored.
                  </p>
                </div>
              </div>
            </>
          )}

          <button
            onClick={async () => {
              await typing.flush()
              await session.endSession('completed')
            }}
            className="w-full font-mono text-sm border border-ink py-3 hover:bg-ink hover:text-paper transition-colors"
          >
            End session
          </button>
        </div>
      </div>
    </main>
  )
}