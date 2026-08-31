'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'

type Concept = { concept_id: string; name: string; subject_id: string; level: number }
type Prereq = { parent_id: string; child_id: string; weight: number }
type Mastery = { concept_id: string; mastery_prob: number; observation_count: number }
type Subject = { subject_id: string; name: string }

const W = 122
const H = 36
const COL_GAP = 20
const ROW_GAP = 78

function tone(m: number | null) {
  if (m === null) return { fill: '#FBFBF8', stroke: '#C8D2C7', text: '#7C877F' }
  if (m < 0.4) return { fill: '#F6E5E4', stroke: '#9E2B2B', text: '#9E2B2B' }
  if (m < 0.7) return { fill: '#F7EEDC', stroke: '#B8721A', text: '#B8721A' }
  return { fill: '#FBFBF8', stroke: '#2E6B4F', text: '#2E6B4F' }
}

export default function ConceptMap({
  concepts,
  prereqs,
  mastery,
  subjects,
}: {
  concepts: Concept[]
  prereqs: Prereq[]
  mastery: Mastery[]
  subjects: Subject[]
}) {
  const [subject, setSubject] = useState<string>(subjects[0]?.subject_id ?? 'all')
  const [sel, setSel] = useState<string | null>(null)

  const masteryOf = useMemo(
    () => new Map(mastery.map((m) => [m.concept_id, Number(m.mastery_prob)])),
    [mastery]
  )

  const shown = useMemo(
    () => concepts.filter((c) => subject === 'all' || c.subject_id === subject),
    [concepts, subject]
  )

  // Lay out by DAG level: level 0 at the bottom, deepest at the top.
  const layout = useMemo(() => {
    const byLevel = new Map<number, Concept[]>()
    for (const c of shown) {
      const list = byLevel.get(c.level) ?? []
      list.push(c)
      byLevel.set(c.level, list)
    }
    const levels = [...byLevel.keys()].sort((a, b) => a - b)
    const maxPerRow = Math.max(...levels.map((l) => byLevel.get(l)!.length), 1)
    const width = maxPerRow * (W + COL_GAP) + COL_GAP
    const height = levels.length * ROW_GAP + 30

    const pos = new Map<string, { x: number; y: number }>()
    for (const lvl of levels) {
      const row = byLevel.get(lvl)!
      const rowWidth = row.length * (W + COL_GAP) - COL_GAP
      const startX = (width - rowWidth) / 2
      const y = height - (levels.indexOf(lvl) + 1) * ROW_GAP
      row.forEach((c, i) => {
        pos.set(c.concept_id, { x: startX + i * (W + COL_GAP), y })
      })
    }
    return { pos, width, height }
  }, [shown])

  const selected = sel ? concepts.find((c) => c.concept_id === sel) ?? null : null
  const selMastery = sel ? masteryOf.get(sel) ?? null : null

  const blockedBy = useMemo(() => {
    if (!sel) return []
    return prereqs
      .filter((p) => p.child_id === sel)
      .map((p) => ({
        id: p.parent_id,
        name: concepts.find((c) => c.concept_id === p.parent_id)?.name ?? p.parent_id,
        m: masteryOf.get(p.parent_id) ?? null,
      }))
      .filter((p) => p.m === null || p.m < 0.7)
  }, [sel, prereqs, concepts, masteryOf])

  const unlocks = useMemo(() => {
    if (!sel) return []
    return prereqs
      .filter((p) => p.parent_id === sel)
      .map((p) => concepts.find((c) => c.concept_id === p.child_id)?.name ?? p.child_id)
  }, [sel, prereqs, concepts])

  if (concepts.length === 0) {
    return (
      <div className="border border-rule bg-card px-6 py-10 text-center">
        <p className="font-display font-semibold text-lg tight">No concepts loaded</p>
        <p className="text-sm text-soft mt-3">
          Run 002_seed_starter_content.sql in the Supabase SQL editor.
        </p>
      </div>
    )
  }

  return (
    <div className="grid xl:grid-cols-12 gap-7">
      <div className="xl:col-span-8">
        <div className="border border-rule bg-card">
          <div className="border-b border-rule px-5 py-3 flex flex-wrap items-center justify-between gap-3">
            <div className="flex gap-2">
              {subjects.map((s) => (
                <button
                  key={s.subject_id}
                  onClick={() => setSubject(s.subject_id)}
                  className={`font-mono text-[10px] px-3 py-1.5 border transition-colors ${
                    subject === s.subject_id
                      ? 'border-ink bg-ink text-paper'
                      : 'border-rule text-soft hover:border-ink hover:text-ink'
                  }`}
                >
                  {s.name}
                </button>
              ))}
            </div>
            <div className="flex items-center gap-3 font-mono text-[10px] text-faint">
              <span className="flex items-center gap-1.5">
                <span className="w-2.5 h-2.5 border" style={{ background: '#F6E5E4', borderColor: '#9E2B2B' }} />
                weak
              </span>
              <span className="flex items-center gap-1.5">
                <span className="w-2.5 h-2.5 border" style={{ background: '#FBFBF8', borderColor: '#2E6B4F' }} />
                strong
              </span>
              <span className="flex items-center gap-1.5">
                <span className="w-2.5 h-2.5 border" style={{ background: '#FBFBF8', borderColor: '#C8D2C7' }} />
                unobserved
              </span>
            </div>
          </div>

          <div className="p-4 overflow-x-auto">
            <svg
              viewBox={`0 0 ${layout.width} ${layout.height}`}
              className="w-full"
              style={{ minWidth: Math.min(layout.width, 640) }}
              role="img"
              aria-label="Concept graph coloured by mastery, prerequisites below dependents."
            >
              {prereqs.map((e) => {
                const a = layout.pos.get(e.parent_id)
                const b = layout.pos.get(e.child_id)
                if (!a || !b) return null
                const pm = masteryOf.get(e.parent_id) ?? null
                const weak = pm !== null && pm < 0.4
                return (
                  <line
                    key={`${e.parent_id}-${e.child_id}`}
                    x1={a.x + W / 2} y1={a.y}
                    x2={b.x + W / 2} y2={b.y + H}
                    stroke={weak ? '#B8721A' : '#C8D2C7'}
                    strokeWidth={weak ? 2 : 1}
                  />
                )
              })}

              {shown.map((c) => {
                const p = layout.pos.get(c.concept_id)
                if (!p) return null
                const m = masteryOf.get(c.concept_id) ?? null
                const t = tone(m)
                const active = sel === c.concept_id
                return (
                  <g
                    key={c.concept_id}
                    onClick={() => setSel(active ? null : c.concept_id)}
                    className="cursor-pointer"
                  >
                    <rect
                      x={p.x} y={p.y} width={W} height={H}
                      fill={t.fill}
                      stroke={active ? '#141A17' : t.stroke}
                      strokeWidth={active ? 2.5 : 1.5}
                    />
                    <text
                      x={p.x + W / 2} y={p.y + 15}
                      textAnchor="middle"
                      fontFamily="var(--font-plex-mono)"
                      fontSize="9.5"
                      fill={t.text}
                    >
                      {c.name.length > 18 ? c.name.slice(0, 17) + '.' : c.name}
                    </text>
                    <text
                      x={p.x + W / 2} y={p.y + 28}
                      textAnchor="middle"
                      fontFamily="var(--font-plex-mono)"
                      fontSize="9"
                      fill="#7C877F"
                    >
                      {m === null ? 'unobserved' : m.toFixed(2)}
                    </text>
                  </g>
                )
              })}
            </svg>
          </div>
        </div>
      </div>

      <div className="xl:col-span-4">
        <div className="border border-rule bg-card sticky top-20">
          <div className="border-b border-rule px-5 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">
              {selected ? 'SELECTED' : 'NO SELECTION'}
            </p>
          </div>
          <div className="px-5 py-5">
            {!selected ? (
              <p className="text-sm text-soft leading-relaxed">
                Click a node to see its mastery, what it unlocks, and which
                prerequisites are holding it back.
              </p>
            ) : (
              <>
                <p className="font-display font-semibold text-xl tight">{selected.name}</p>
                <p className="font-mono text-[10px] text-faint mt-1">
                  {selected.subject_id.toUpperCase()} &middot; level {selected.level}
                </p>

                <div className="mt-5">
                  <div className="flex items-baseline justify-between mb-1.5">
                    <span className="font-mono text-[10px] text-faint">MASTERY</span>
                    <span className="font-mono text-xs">
                      {selMastery === null ? 'unobserved' : selMastery.toFixed(2)}
                    </span>
                  </div>
                  <div className="h-1.5 bg-rule relative">
                    <div
                      className={
                        selMastery === null
                          ? 'bg-rule'
                          : selMastery < 0.4
                          ? 'bg-alarm'
                          : selMastery < 0.7
                          ? 'bg-amber'
                          : 'bg-mastery'
                      }
                      style={{
                        width: `${(selMastery ?? 0) * 100}%`,
                        position: 'absolute',
                        inset: '0 auto 0 0',
                      }}
                    />
                  </div>
                </div>

                {blockedBy.length > 0 && (
                  <div className="mt-6 border-l-2 border-alarm pl-4">
                    <p className="font-mono text-[10px] eyebrow text-alarm mb-2">
                      WEAK PREREQUISITES
                    </p>
                    <ul className="space-y-1">
                      {blockedBy.map((b) => (
                        <li key={b.id} className="font-mono text-xs">
                          {b.name}{' '}
                          <span className="text-faint">
                            {b.m === null ? '(unobserved)' : b.m.toFixed(2)}
                          </span>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}

                <div className="mt-6">
                  <p className="font-mono text-[10px] eyebrow text-faint mb-2">UNLOCKS</p>
                  {unlocks.length ? (
                    <ul className="space-y-1">
                      {unlocks.map((u) => (
                        <li key={u} className="font-mono text-xs text-soft">{u}</li>
                      ))}
                    </ul>
                  ) : (
                    <p className="font-mono text-xs text-faint">Nothing downstream</p>
                  )}
                </div>

                <Link
                  href={`/study/session?concept=${encodeURIComponent(selected.concept_id)}`}
                  className="block text-center mt-7 font-mono text-xs border border-ink py-2.5 hover:bg-ink hover:text-paper transition-colors"
                >
                  Practise this concept
                </Link>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}