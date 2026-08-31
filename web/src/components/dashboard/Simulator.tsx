'use client'

import { useState } from 'react'

type Subject = {
  id: string
  name: string
  mastery: number
  weight: number   // exam weight for the current target
  ceiling: number  // diminishing returns kick in past this
}

const SUBJECTS: Subject[] = [
  { id: 'apt', name: 'Aptitude', mastery: 0.66, weight: 0.40, ceiling: 6 },
  { id: 'dsa', name: 'DSA', mastery: 0.43, weight: 0.25, ceiling: 10 },
  { id: 'dbms', name: 'DBMS', mastery: 0.71, weight: 0.15, ceiling: 5 },
  { id: 'cn', name: 'Computer Networks', mastery: 0.54, weight: 0.20, ceiling: 8 },
]

const BUDGET = 12

/** Mastery gain saturates: the first hour on a weak topic is worth far more
 *  than the sixth on a strong one. */
function projectedMastery(s: Subject, hours: number) {
  const room = 1 - s.mastery
  const gain = room * (1 - Math.exp(-hours / s.ceiling))
  return Math.min(0.98, s.mastery + gain)
}

function score(alloc: Record<string, number>) {
  return SUBJECTS.reduce(
    (a, s) => a + projectedMastery(s, alloc[s.id] ?? 0) * s.weight * 100,
    0
  )
}

const BASELINE = score({})

export default function Simulator() {
  const [alloc, setAlloc] = useState<Record<string, number>>({
    apt: 3, dsa: 3, dbms: 2, cn: 2,
  })

  const used = Object.values(alloc).reduce((a, b) => a + b, 0)
  const left = BUDGET - used
  const projected = score(alloc)
  const delta = projected - BASELINE

  function set(id: string, v: number) {
    const others = used - (alloc[id] ?? 0)
    setAlloc({ ...alloc, [id]: Math.min(v, BUDGET - others) })
  }

  // Best single extra hour, given the current allocation
  const bestNext = SUBJECTS.map((s) => ({
    name: s.name,
    gain: score({ ...alloc, [s.id]: (alloc[s.id] ?? 0) + 1 }) - projected,
  })).sort((a, b) => b.gain - a.gain)[0]

  return (
    <div className="grid xl:grid-cols-12 gap-7">
      <div className="xl:col-span-7">
        <div className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3 flex items-center justify-between">
            <p className="font-mono text-[10px] eyebrow text-faint">ALLOCATE {BUDGET} HOURS</p>
            <p
              className={`font-mono text-[10px] ${left === 0 ? 'text-mastery' : 'text-amber'}`}
            >
              {left === 0 ? 'FULLY ALLOCATED' : `${left}H UNASSIGNED`}
            </p>
          </div>

          <div className="px-6 py-6 space-y-7">
            {SUBJECTS.map((s) => {
              const h = alloc[s.id] ?? 0
              const after = projectedMastery(s, h)
              return (
                <div key={s.id}>
                  <div className="flex flex-wrap items-baseline justify-between gap-3 mb-2">
                    <span className="font-mono text-xs">{s.name}</span>
                    <span className="font-mono text-[10px] text-faint">
                      weight {s.weight.toFixed(2)} &middot; {s.mastery.toFixed(2)}{' '}
                      &rarr; <span className="text-ink">{after.toFixed(2)}</span>
                    </span>
                  </div>

                  <input
                    type="range"
                    min={0}
                    max={BUDGET}
                    value={h}
                    onChange={(e) => set(s.id, Number(e.target.value))}
                    className="w-full accent-[#141A17]"
                    aria-label={`Hours on ${s.name}`}
                  />

                  <div className="flex items-center justify-between mt-1.5">
                    <span className="font-mono text-[10px] text-faint">{h}h</span>
                    <div className="flex-1 mx-4 h-1 bg-rule relative">
                      <div
                        className="bg-faint"
                        style={{ width: `${s.mastery * 100}%`, position: 'absolute', inset: '0 auto 0 0' }}
                      />
                      <div
                        className="bg-amber"
                        style={{
                          left: `${s.mastery * 100}%`,
                          width: `${(after - s.mastery) * 100}%`,
                          position: 'absolute',
                          top: 0,
                          bottom: 0,
                        }}
                      />
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      </div>

      <div className="xl:col-span-5 space-y-7">
        <div className="border border-rule bg-ink text-paper px-6 py-7">
          <p className="font-mono text-[10px] eyebrow text-paper/50 mb-4">
            PROJECTED SCORE &middot; TCS NQT
          </p>
          <div className="flex items-baseline gap-4">
            <span className="font-display font-extrabold text-5xl tight">
              {projected.toFixed(0)}
            </span>
            <span className="font-mono text-sm text-amber">
              +{delta.toFixed(1)} from {BASELINE.toFixed(0)}
            </span>
          </div>
          <div className="h-2 bg-paper/10 mt-6 relative">
            <div
              className="bg-paper/30"
              style={{ width: `${BASELINE}%`, position: 'absolute', inset: '0 auto 0 0' }}
            />
            <div
              className="bg-amber"
              style={{
                left: `${BASELINE}%`,
                width: `${delta}%`,
                position: 'absolute',
                top: 0,
                bottom: 0,
              }}
            />
          </div>
          <p className="text-sm text-paper/60 mt-5 leading-relaxed">
            Gains saturate. The sixth hour on a subject you already know is worth a
            fraction of the first hour on one you do not.
          </p>
        </div>

        <div className="border-l-2 border-amber bg-amber-wash px-5 py-4">
          <p className="font-mono text-[10px] eyebrow text-amber mb-2">BEST NEXT HOUR</p>
          <p className="text-sm">
            One more hour on <span className="font-semibold">{bestNext.name}</span> adds{' '}
            {bestNext.gain.toFixed(2)} points &mdash; more than any other single hour
            from here.
          </p>
        </div>

        <div className="border border-rule bg-card px-5 py-5">
          <p className="font-mono text-[10px] eyebrow text-faint mb-3">WHAT THIS IGNORES</p>
          <p className="text-xs text-soft leading-relaxed">
            Forgetting between now and the exam, and the fact that unlocking a
            prerequisite raises the ceiling on everything above it. The scheduler
            accounts for both; this slider does not.
          </p>
        </div>
      </div>
    </div>
  )
}