'use client'

import { useEffect, useRef, useState } from 'react'

type Node = {
  id: string
  label: string
  x: number
  y: number
  tier: number
}

const NODES: Node[] = [
  { id: 'arrays',    label: 'Arrays',         x: 120, y: 278, tier: 0 },
  { id: 'loops',     label: 'Loops',          x: 380, y: 278, tier: 0 },
  { id: 'sorting',   label: 'Sorting basics', x: 120, y: 198, tier: 1 },
  { id: 'recursion', label: 'Recursion',      x: 380, y: 198, tier: 1 },
  { id: 'pq',        label: 'Priority queue', x: 105, y: 118, tier: 2 },
  { id: 'graphrep',  label: 'Graph repr.',    x: 250, y: 118, tier: 2 },
  { id: 'bfs',       label: 'BFS',            x: 395, y: 118, tier: 2 },
  { id: 'dijkstra',  label: 'Dijkstra',       x: 250, y: 38,  tier: 3 },
]

const EDGES: [string, string][] = [
  ['arrays', 'sorting'],
  ['arrays', 'pq'],
  ['loops', 'recursion'],
  ['sorting', 'pq'],
  ['recursion', 'graphrep'],
  ['recursion', 'bfs'],
  ['pq', 'dijkstra'],
  ['graphrep', 'dijkstra'],
  ['bfs', 'dijkstra'],
]

const BLAME_PATH: [string, string][] = [
  ['dijkstra', 'pq'],
  ['pq', 'sorting'],
]

const W = 110
const H = 40

function node(id: string) {
  return NODES.find((n) => n.id === id)!
}

/** Maps overall progress onto a 0..1 range for one stage. */
function stage(p: number, from: number, to: number) {
  return Math.max(0, Math.min(1, (p - from) / (to - from)))
}

const CAPTIONS = [
  { at: 0.02, text: 'Every subject is a graph, built from the foundations up.' },
  { at: 0.34, text: 'Prerequisites carry weights, not just links.' },
  { at: 0.52, text: 'Six of eight Dijkstra attempts fail.' },
  { at: 0.70, text: 'Blame propagates downward, weighted by what you already know.' },
  { at: 0.88, text: 'The root is two levels below where you failed.' },
]

export default function ScrollScene() {
  const wrapRef = useRef<HTMLDivElement>(null)
  const [p, setP] = useState(0)
  const [reduced, setReduced] = useState(false)

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setReduced(true)
      setP(1)
      return
    }

    const el = wrapRef.current
    if (!el) return

    let frame = 0
    const update = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        const rect = el.getBoundingClientRect()
        const travel = rect.height - window.innerHeight
        if (travel <= 0) return setP(1)
        setP(Math.max(0, Math.min(1, -rect.top / travel)))
      })
    }

    update()
    window.addEventListener('scroll', update, { passive: true })
    window.addEventListener('resize', update)
    return () => {
      window.removeEventListener('scroll', update)
      window.removeEventListener('resize', update)
      cancelAnimationFrame(frame)
    }
  }, [])

  // Stage timings
  const build = stage(p, 0.05, 0.34)   // nodes appear tier by tier
  const link = stage(p, 0.30, 0.50)    // edges draw
  const fail = stage(p, 0.50, 0.62)    // Dijkstra turns red
  const blame = stage(p, 0.62, 0.86)   // blame flows down
  const root = stage(p, 0.84, 0.96)    // root ignites

  const caption =
    [...CAPTIONS].reverse().find((c) => p >= c.at)?.text ?? CAPTIONS[0].text

  const tierVisible = (tier: number) => {
    const start = tier * 0.25
    return Math.max(0, Math.min(1, (build - start) / 0.25))
  }

  return (
    <section ref={wrapRef} className="rule relative h-[320vh]">
      <div className="sticky top-16 h-[calc(100vh-4rem)] flex items-center">
        <div className="mx-auto max-w-6xl w-full px-6">
          <div className="grid md:grid-cols-12 gap-10 items-center">
            <div className="md:col-span-4">
              <p className="font-mono text-[11px] eyebrow text-faint mb-6">CONCEPT GRAPH</p>
              <h2 className="font-display font-extrabold text-3xl md:text-4xl tight leading-tight">
                Nothing is scheduled<br />before its<br />prerequisites.
              </h2>
              <p className="mt-7 text-soft leading-relaxed min-h-[4.5rem]">{caption}</p>
              <div className="mt-8 h-px bg-rule relative" aria-hidden="true">
                <div
                  className="absolute inset-y-0 left-0 bg-amber"
                  style={{ width: `${p * 100}%` }}
                />
              </div>
            </div>

            <div className="md:col-span-8">
              <div className="border border-rule bg-card p-4 md:p-6">
                <svg viewBox="0 0 500 330" className="w-full" role="img"
                  aria-label="A prerequisite graph assembling from foundations upward, then a Dijkstra failure propagating blame down to sorting basics.">

                  {EDGES.map(([from, to]) => {
                    const a = node(from)
                    const b = node(to)
                    const onBlame = BLAME_PATH.some(
                      ([x, y]) => (x === to && y === from)
                    )
                    const vis = Math.min(tierVisible(a.tier), link)
                    const blamed = onBlame ? blame : 0
                    return (
                      <line
                        key={`${from}-${to}`}
                        x1={a.x} y1={a.y}
                        x2={b.x} y2={b.y + H / 2}
                        stroke={blamed > 0.15 ? '#B8721A' : '#C8D2C7'}
                        strokeWidth={blamed > 0.15 ? 2.5 : 1}
                        opacity={vis}
                      />
                    )
                  })}

                  {NODES.map((n) => {
                    const vis = tierVisible(n.tier)
                    const isFail = n.id === 'dijkstra'
                    const isRoot = n.id === 'sorting'
                    const isMid = n.id === 'pq'

                    let fill = '#FBFBF8'
                    let stroke = '#C8D2C7'
                    let text = '#4A554E'
                    let sw = 1

                    if (isFail && fail > 0.3) {
                      fill = '#F6E5E4'; stroke = '#9E2B2B'; text = '#9E2B2B'; sw = 2
                    }
                    if (isMid && blame > 0.4) {
                      stroke = '#B8721A'; text = '#141A17'; sw = 2
                    }
                    if (isRoot && root > 0.3) {
                      fill = '#F7EEDC'; stroke = '#B8721A'; text = '#B8721A'; sw = 2.5
                    }

                    return (
                      <g key={n.id} opacity={vis}
                         transform={`translate(0, ${(1 - vis) * 10})`}>
                        <rect
                          x={n.x - W / 2} y={n.y - H / 2}
                          width={W} height={H}
                          fill={fill} stroke={stroke} strokeWidth={sw}
                        />
                        <text
                          x={n.x} y={n.y + 4}
                          textAnchor="middle"
                          fontFamily="var(--font-plex-mono)"
                          fontSize="11"
                          fill={text}
                        >
                          {n.label}
                        </text>
                      </g>
                    )
                  })}

                  {fail > 0.5 && (
                    <text x={250} y={14} textAnchor="middle"
                      fontFamily="var(--font-plex-mono)" fontSize="10"
                      fill="#9E2B2B" opacity={fail}>
                      6 / 8 FAILED
                    </text>
                  )}

                  {blame > 0.5 && (
                    <text x={168} y={82} textAnchor="middle"
                      fontFamily="var(--font-plex-mono)" fontSize="10"
                      fill="#B8721A" opacity={blame}>
                      62%
                    </text>
                  )}

                  {root > 0.4 && (
                    <text x={120} y={236} textAnchor="middle"
                      fontFamily="var(--font-plex-mono)" fontSize="10"
                      fill="#B8721A" opacity={root}>
                      root cause &middot; mastery 0.31
                    </text>
                  )}
                </svg>
              </div>
              {reduced && (
                <p className="font-mono text-[10px] text-faint mt-3">
                  Animation reduced per your system settings.
                </p>
              )}
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}