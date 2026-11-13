'use client'

import { useMemo, useState } from 'react'
import {
  type SimSubject,
  bestNextHour,
  initialAllocation,
  projectedMastery,
  readiness,
} from '@/lib/simulator'

/**
 * Subjects, mastery and exam weights come from the student's own rows
 * (see app/dashboard/simulate/page.tsx); nothing here is sample data.
 */
export default function Simulator({
  subjects,
  budget,
  examName,
}: {
  subjects: SimSubject[]
  budget: number
  examName: string | null
}) {
  const baseline = useMemo(() => readiness(subjects, {}), [subjects])
  const [alloc, setAlloc] = useState<Record<string, number>>(() =>
    initialAllocation(subjects, budget)
  )

  const used = Object.values(alloc).reduce((a, b) => a + b, 0)
  const left = budget - used
  const projected = readiness(subjects, alloc)
  const delta = projected - baseline

  function set(id: string, v: number) {
    const others = used - (alloc[id] ?? 0)
    setAlloc({ ...alloc, [id]: Math.min(v, budget - others) })
  }

  const bestNext = bestNextHour(subjects, alloc)

  return (
    <div className="grid xl:grid-cols-12 gap-7">
      <div className="xl:col-span-7">
        <div className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3 flex items-center justify-between">
            <p className="font-mono text-[10px] eyebrow text-faint">ALLOCATE {budget} HOURS</p>
            <p
              className={`font-mono text-[10px] ${left === 0 ? 'text-mastery' : 'text-amber'}`}
            >
              {left === 0 ? 'FULLY ALLOCATED' : `${left}H UNASSIGNED`}
            </p>
          </div>

          <div className="px-6 py-6 space-y-7">
            {subjects.map((s) => {
              const h = alloc[s.id] ?? 0
              const after = projectedMastery(s, h)
              return (
                <div key={s.id}>
                  <div className="flex flex-wrap items-baseline justify-between gap-3 mb-2">
                    <span className="font-mono text-xs">
                      {s.name}
                      <span className="text-faint">
                        {' '}&middot; {s.observed}/{s.concepts} concepts seen
                      </span>
                    </span>
                    <span className="font-mono text-[10px] text-faint">
                      weight {s.weight.toFixed(2)} &middot; {s.mastery.toFixed(2)}{' '}
                      &rarr; <span className="text-ink">{after.toFixed(2)}</span>
                    </span>
                  </div>

                  <input
                    type="range"
                    min={0}
                    max={budget}
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
            PROJECTED READINESS &middot; {examName ?? 'ALL subjects'}
          </p>
          <div className="flex items-baseline gap-4">
            <span className="font-display font-extrabold text-5xl tight">
              {projected.toFixed(0)}
            </span>
            <span className="font-mono text-sm text-amber">
              +{delta.toFixed(1)} from {baseline.toFixed(0)}
            </span>
          </div>
          <div className="h-2 bg-paper/10 mt-6 relative">
            <div
              className="bg-paper/30"
              style={{ width: `${baseline}%`, position: 'absolute', inset: '0 auto 0 0' }}
            />
            <div
              className="bg-amber"
              style={{
                left: `${baseline}%`,
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
          {bestNext && (
            <p className="text-sm">
              One more hour on <span className="font-semibold">{bestNext.name}</span> adds{' '}
              {bestNext.gain.toFixed(2)} points &mdash; more than any other single hour
              from here.
            </p>
          )}
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