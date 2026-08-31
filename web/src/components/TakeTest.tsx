'use client'

import { useState } from 'react'
import Link from 'next/link'

type Option = {
  id: string
  body: string
  correct: boolean
  misconception?: string
  note: string
}

const QUESTION = {
  concept: 'dbms.normalization_3nf',
  stem: 'A relation R(A, B, C) has functional dependencies A \u2192 B and B \u2192 C, with A as the only candidate key. Which normal form does R violate?',
  options: [
    {
      id: 'a',
      body: 'First normal form',
      correct: false,
      misconception: 'Treats any dependency chain as an atomicity problem',
      note: '1NF is only about atomic attribute values. Nothing here says an attribute holds a set.',
    },
    {
      id: 'b',
      body: 'Second normal form',
      correct: false,
      misconception: 'Confuses transitive dependency with partial dependency',
      note: '2NF violations need a partial dependency on part of a composite key. A is a single attribute, so there is no partial dependency available.',
    },
    {
      id: 'c',
      body: 'Third normal form',
      correct: true,
      note: 'C depends on A only through B. That transitive dependency is exactly what 3NF forbids.',
    },
    {
      id: 'd',
      body: 'No violation',
      correct: false,
      misconception: 'Does not recognise transitive dependency as a violation',
      note: 'A \u2192 B \u2192 C is a transitive dependency, and R is therefore not in 3NF.',
    },
  ] as Option[],
}

const CONFIDENCE = [
  { value: 1, label: 'Not sure' },
  { value: 2, label: 'Fairly sure' },
  { value: 3, label: 'Certain' },
]

export default function TakeTest() {
  const [confidence, setConfidence] = useState<number | null>(null)
  const [picked, setPicked] = useState<Option | null>(null)

  const reset = () => {
    setConfidence(null)
    setPicked(null)
  }

  const verdict = (() => {
    if (!picked || !confidence) return null
    if (picked.correct) {
      return confidence === 3
        ? { tag: 'MASTERED', tone: 'mastery', line: 'Correct and certain. This goes to review, not practice.' }
        : { tag: 'UNCERTAIN CORRECT', tone: 'ink', line: 'Correct, but you were not sure. Credited less, and you will see this concept again sooner.' }
    }
    if (confidence === 3) {
      return { tag: 'CONFIDENTLY WRONG', tone: 'alarm', line: 'A held belief, not a slip. This is the highest-priority thing to fix.' }
    }
    return { tag: 'KNOWN GAP', tone: 'ink', line: 'You already suspected this one. Straightforward to close.' }
  })()

  return (
    <section id="test" className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-12">
          <div className="md:col-span-4">
            <p className="font-mono text-[11px] eyebrow text-faint mb-6">TRY ONE</p>
            <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
              This is what<br />one question<br />looks like.
            </h2>
            <p className="mt-6 text-soft leading-relaxed">
              Declare your confidence first, then answer. What comes back is not a score &mdash;
              it is a reading of what you believe and how firmly.
            </p>
            {picked && (
              <button
                onClick={reset}
                className="mt-7 font-mono text-xs text-soft border-b border-rule pb-0.5 hover:text-ink hover:border-ink"
              >
                Try a different answer
              </button>
            )}
          </div>

          <div className="md:col-span-8">
            <div className="border border-rule bg-card">
              <div className="border-b border-rule px-6 py-3 flex items-center justify-between">
                <span className="font-mono text-[10px] eyebrow text-faint">DBMS &middot; NORMALIZATION &middot; 3NF</span>
                <span className="font-mono text-[10px] text-faint">MEDIAN 52s</span>
              </div>

              <div className="p-6">
                <p className="text-lg leading-relaxed mb-7">{QUESTION.stem}</p>

                <p className="font-mono text-[10px] eyebrow text-faint mb-3">
                  STEP 1 &mdash; HOW SURE ARE YOU?
                </p>
                <div className="flex flex-wrap gap-2 mb-8">
                  {CONFIDENCE.map((c) => (
                    <button
                      key={c.value}
                      onClick={() => setConfidence(c.value)}
                      disabled={!!picked}
                      className={`font-mono text-xs px-4 py-2 border transition-colors disabled:opacity-60 ${
                        confidence === c.value
                          ? 'border-ink bg-ink text-paper'
                          : 'border-rule text-soft hover:border-ink hover:text-ink'
                      }`}
                    >
                      {c.label}
                    </button>
                  ))}
                </div>

                <p className="font-mono text-[10px] eyebrow text-faint mb-3">
                  STEP 2 &mdash; YOUR ANSWER
                </p>
                <div className="space-y-2">
                  {QUESTION.options.map((o) => {
                    const chosen = picked?.id === o.id
                    const revealCorrect = picked && o.correct
                    return (
                      <button
                        key={o.id}
                        onClick={() => confidence && setPicked(o)}
                        disabled={!confidence || !!picked}
                        className={`w-full text-left px-5 py-3.5 border transition-colors disabled:cursor-not-allowed ${
                          chosen && !o.correct
                            ? 'border-alarm bg-alarm-wash'
                            : revealCorrect
                            ? 'border-mastery bg-white'
                            : 'border-rule hover:border-ink disabled:hover:border-rule'
                        } ${!confidence ? 'opacity-50' : ''}`}
                      >
                        <span className="font-mono text-xs text-faint mr-3">
                          {o.id.toUpperCase()}
                        </span>
                        <span className="text-sm">{o.body}</span>
                      </button>
                    )
                  })}
                </div>

                {!confidence && (
                  <p className="font-mono text-[10px] text-faint mt-4">
                    Pick a confidence level first &mdash; that is the whole point.
                  </p>
                )}

                {picked && verdict && (
                  <div className="mt-8 border-t border-rule pt-6">
                    <div className="flex flex-wrap items-center gap-3 mb-4">
                      <span
                        className={`font-mono text-[10px] eyebrow px-2.5 py-1 ${
                          verdict.tone === 'alarm'
                            ? 'bg-alarm text-paper'
                            : verdict.tone === 'mastery'
                            ? 'bg-mastery text-paper'
                            : 'bg-ink text-paper'
                        }`}
                      >
                        {verdict.tag}
                      </span>
                      {picked.misconception && (
                        <span className="font-mono text-[10px] text-amber">
                          MISCONCEPTION LOGGED
                        </span>
                      )}
                    </div>

                    <p className="text-sm text-soft leading-relaxed mb-4">{verdict.line}</p>

                    {picked.misconception && (
                      <div className="border-l-2 border-amber pl-4 mb-4">
                        <p className="font-mono text-[10px] eyebrow text-faint mb-1.5">
                          NAMED BELIEF
                        </p>
                        <p className="text-sm text-ink">{picked.misconception}</p>
                      </div>
                    )}

                    <p className="text-sm text-soft leading-relaxed">{picked.note}</p>

                    <p className="font-mono text-[11px] text-faint mt-6">
                      In the real test this feeds twenty of these into your concept graph
                      and generates week one.
                    </p>
                  </div>
                )}
              </div>
            </div>

            <div className="mt-6 flex flex-wrap items-center gap-4">
              <Link
                href="/signup"
                className="font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors"
              >
                Take the full test
              </Link>
              <span className="font-mono text-xs text-faint">
                20 questions &middot; about 12 minutes &middot; no score at the end
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}