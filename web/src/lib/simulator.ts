/**
 * What-if model behind the Simulate page. Pure functions, no I/O, so the
 * page can run it in the browser on every slider move.
 *
 * Same saturation curve as the ML service's POST /simulate:
 *   projected = m + (1 - m) * (1 - exp(-hours / ceiling)),  ceiling = 4 + 8(1 - m)
 * so the numbers agree whichever one is asked.
 */

/** Mastery assumed for a concept with no attempts yet (BKT p_init). */
export const PRIOR = 0.15
const CAP = 0.98

export type SimSubject = {
  id: string
  name: string
  mastery: number   // mean over ALL concepts in the subject
  weight: number    // share of the target exam, sums to 1 across subjects
  concepts: number
  observed: number  // concepts with at least one attempt
}

export function buildSubjects(input: {
  concepts: { concept_id: string; subject_id: string }[]
  subjects: { subject_id: string; name: string }[]
  mastery: { concept_id: string; mastery_prob: number | string }[]
  examWeights: { concept_id: string; weight: number | string }[]
}): SimSubject[] {
  const m = new Map(input.mastery.map((r) => [r.concept_id, Number(r.mastery_prob)]))
  const w = new Map(input.examWeights.map((r) => [r.concept_id, Number(r.weight)]))

  const rows = input.subjects
    .map((s) => {
      const cs = input.concepts.filter((c) => c.subject_id === s.subject_id)
      if (cs.length === 0) return null
      const mastery = cs.reduce((a, c) => a + (m.get(c.concept_id) ?? PRIOR), 0) / cs.length
      const raw = w.size
        ? cs.reduce((a, c) => a + (w.get(c.concept_id) ?? 1), 0) / cs.length // 1 = neutral, as in the planner
        : 1
      return {
        id: s.subject_id,
        name: s.name,
        mastery,
        raw,
        concepts: cs.length,
        observed: cs.filter((c) => m.has(c.concept_id)).length,
      }
    })
    .filter((r): r is NonNullable<typeof r> => r !== null)

  const total = rows.reduce((a, r) => a + r.raw, 0) || 1
  return rows.map(({ raw, ...r }) => ({ ...r, weight: raw / total }))
}

export function projectedMastery(s: SimSubject, hours: number): number {
  const ceiling = 4 + 8 * (1 - s.mastery)
  const gain = (1 - s.mastery) * (1 - Math.exp(-hours / ceiling))
  return Math.min(CAP, Math.max(s.mastery, s.mastery + gain))
}

/** Weighted mean of projected mastery, on a 0-100 scale. */
export function readiness(subjects: SimSubject[], alloc: Record<string, number>): number {
  return subjects.reduce(
    (a, s) => a + projectedMastery(s, alloc[s.id] ?? 0) * s.weight * 100,
    0
  )
}

export function bestNextHour(subjects: SimSubject[], alloc: Record<string, number>) {
  const now = readiness(subjects, alloc)
  return subjects
    .map((s) => ({
      id: s.id,
      name: s.name,
      gain: readiness(subjects, { ...alloc, [s.id]: (alloc[s.id] ?? 0) + 1 }) - now,
    }))
    .sort((a, b) => b.gain - a.gain)[0] ?? null
}

/** Starting split: whole hours, weakest-weighted subjects first. */
export function initialAllocation(subjects: SimSubject[], budget: number) {
  const alloc: Record<string, number> = {}
  for (let h = 0; h < budget; h++) {
    const best = bestNextHour(subjects, alloc)
    if (!best) break
    alloc[best.id] = (alloc[best.id] ?? 0) + 1
  }
  return alloc
}
