import { createClient } from '@/lib/supabase/server'

/**
 * Real analytics computed from the student's own rows.
 *
 * Blame propagation and the diagnosis counts need no trained model, so they
 * produce genuine output from the first attempt onward. Anything that DOES
 * need fitting (forgetting half-life, focus curve) returns null here and the
 * UI says so rather than inventing a number.
 */

export type BlameStep = { concept: string; conceptId: string; share: number; mastery: number }

export type RootCause = {
  failedConcept: string
  failedConceptId: string
  rootConcept: string
  rootConceptId: string
  share: number
  rootMastery: number
  failures: number
  trace: BlameStep[]
  /** false when the prerequisites are solid and the weakness is the concept
   *  itself. That is a real diagnosis, not a missing one. */
  isTraced: boolean
}

export type SubjectMastery = {
  subject: string
  subjectId: string
  mastery: number
  concepts: number
  observed: number
}

export type FixItem = {
  concept: string
  conceptId: string
  subject: string
  blame: number
  belief: string
  times: number
}

export type DiagnosisCounts = {
  sureCorrect: number
  sureWrong: number
  unsureCorrect: number
  unsureWrong: number
  total: number
  errorMix: { kind: string; n: number }[]
}

export type Analytics = {
  attemptCount: number
  hasEnoughForDiagnosis: boolean
  rootCause: RootCause | null
  subjects: SubjectMastery[]
  fixFirst: FixItem[]
  diagnosis: DiagnosisCounts
  weakest: {
    conceptId: string
    name: string
    subjectId: string
    mastery: number
    observations: number
  }[]
  medianObservations: number
  thinEstimate: boolean
  focusHalfLife: number | null
  sessionsTracked: number
  activeMinutes: number
  decayingCount: number | null
}

const STOP_MASTERY = 0.8   // stop recursing into concepts the student knows
const MAX_DEPTH = 4

export async function getAnalytics(studentId: string): Promise<Analytics> {
  const supabase = await createClient()

  const [
    { data: attempts },
    { data: concepts },
    { data: prereqs },
    { data: mastery },
    { data: subjects },
    { data: sessions },
  ] = await Promise.all([
    supabase
      .from('attempts')
      .select(`
        attempt_id, is_correct, confidence, error_type, created_at,
        questions:question_id ( primary_concept_id ),
        options:chosen_option_id ( misconception_id,
          misconceptions:misconception_id ( label, concept_id ) )
      `)
      .eq('student_id', studentId)
      .order('created_at', { ascending: false })
      .limit(500),
    supabase.from('concepts').select('concept_id, name, subject_id, level'),
    supabase.from('prerequisites').select('parent_id, child_id, weight'),
    supabase
      .from('mastery')
      .select('concept_id, mastery_prob, uncertainty, observation_count')
      .eq('student_id', studentId),
    supabase.from('subjects').select('subject_id, name'),
    supabase
      .from('study_sessions')
      .select('session_id, active_minutes, started_at')
      .eq('student_id', studentId)
      .not('active_minutes', 'is', null),
  ])

  const A = attempts ?? []
  const C = concepts ?? []
  const P = prereqs ?? []
  const M = mastery ?? []
  const S = subjects ?? []
  const SESS = sessions ?? []

  const conceptById = new Map(C.map((c) => [c.concept_id, c]))
  const masteryById = new Map(
    M.map((m) => [
      m.concept_id,
      {
        p: Number(m.mastery_prob),
        u: Number(m.uncertainty),
        n: Number(m.observation_count ?? 0),
      },
    ])
  )
  const parentsOf = new Map<string, { id: string; w: number }[]>()
  for (const e of P) {
    const list = parentsOf.get(e.child_id) ?? []
    list.push({ id: e.parent_id, w: Number(e.weight) })
    parentsOf.set(e.child_id, list)
  }

  const mOf = (id: string) => masteryById.get(id)?.p ?? 0.15
  const uOf = (id: string) => masteryById.get(id)?.u ?? 1.0
  const nameOf = (id: string) => conceptById.get(id)?.name ?? id

  // ---------- Diagnosis counts ----------
  const diagnosis: DiagnosisCounts = {
    sureCorrect: 0,
    sureWrong: 0,
    unsureCorrect: 0,
    unsureWrong: 0,
    total: A.length,
    errorMix: [],
  }
  const mix = new Map<string, number>()
  for (const a of A) {
    const sure = (a.confidence ?? 2) === 3
    if (a.is_correct) sure ? diagnosis.sureCorrect++ : diagnosis.unsureCorrect++
    else sure ? diagnosis.sureWrong++ : diagnosis.unsureWrong++
    if (!a.is_correct && a.error_type) {
      mix.set(a.error_type, (mix.get(a.error_type) ?? 0) + 1)
    }
  }
  diagnosis.errorMix = [...mix.entries()]
    .map(([kind, n]) => ({ kind, n }))
    .sort((x, y) => y.n - x.n)

  // ---------- Failures by concept ----------
  const failuresByConcept = new Map<string, number>()
  for (const a of A) {
    if (a.is_correct) continue
    const q = a.questions as unknown as { primary_concept_id: string } | null
    if (!q?.primary_concept_id) continue
    failuresByConcept.set(
      q.primary_concept_id,
      (failuresByConcept.get(q.primary_concept_id) ?? 0) + 1
    )
  }

  // ---------- Blame propagation ----------
  // blame(p) = weight(p -> c) * (1 - mastery(p)) * uncertainty(p), normalised.
  function propagate(conceptId: string): BlameStep[] {
    const trace: BlameStep[] = [
      { concept: nameOf(conceptId), conceptId, share: 1, mastery: mOf(conceptId) },
    ]
    let current = conceptId
    for (let d = 0; d < MAX_DEPTH; d++) {
      const parents = parentsOf.get(current)
      if (!parents || parents.length === 0) break

      const scored = parents.map((p) => ({
        id: p.id,
        raw: p.w * (1 - mOf(p.id)) * uOf(p.id),
      }))
      const total = scored.reduce((a, s) => a + s.raw, 0)
      if (total <= 0) break

      scored.sort((a, b) => b.raw - a.raw)
      const top = scored[0]

      // Stop BEFORE appending a concept the student already knows. Appending
      // first and checking afterwards named strongly-mastered prerequisites
      // as root causes, which is the opposite of the point: the trace should
      // bottom out at the last genuinely weak concept.
      if (mOf(top.id) >= STOP_MASTERY) break

      trace.push({
        concept: nameOf(top.id),
        conceptId: top.id,
        share: top.raw / total,
        mastery: mOf(top.id),
      })
      current = top.id
    }
    return trace
  }

  let rootCause: RootCause | null = null
  const ranked = [...failuresByConcept.entries()].sort((a, b) => b[1] - a[1])
  if (ranked.length > 0) {
    const [failedId, failures] = ranked[0]
    const trace = propagate(failedId)
    const last = trace[trace.length - 1]

    // A trace of length 1 means every prerequisite is already solid, so the
    // weakness is the concept itself. Reported as such rather than suppressed:
    // "your prerequisites are fine, the gap is here" is exactly the kind of
    // answer the graph exists to give.
    rootCause = {
      failedConcept: nameOf(failedId),
      failedConceptId: failedId,
      rootConcept: last.concept,
      rootConceptId: last.conceptId,
      share: trace.length > 1 ? trace[1].share : 1,
      rootMastery: last.mastery,
      failures,
      trace,
      isTraced: trace.length > 1,
    }
  }

  // ---------- Fix-first queue, from named misconceptions ----------
  const beliefs = new Map<string, { label: string; conceptId: string; n: number }>()
  for (const a of A) {
    if (a.is_correct) continue
    const opt = a.options as unknown as {
      misconceptions: { label: string; concept_id: string } | null
    } | null
    const m = opt?.misconceptions
    if (!m) continue
    const key = m.label
    const prev = beliefs.get(key)
    beliefs.set(key, {
      label: m.label,
      conceptId: m.concept_id,
      n: (prev?.n ?? 0) + 1,
    })
  }
  const beliefTotal = [...beliefs.values()].reduce((a, b) => a + b.n, 0) || 1
  const fixFirst: FixItem[] = [...beliefs.values()]
    .sort((a, b) => b.n - a.n)
    .slice(0, 5)
    .map((b) => ({
      concept: nameOf(b.conceptId),
      conceptId: b.conceptId,
      subject: conceptById.get(b.conceptId)?.subject_id?.toUpperCase() ?? '',
      blame: b.n / beliefTotal,
      belief: b.label,
      times: b.n,
    }))

  // ---------- Mastery by subject ----------
  const subjectName = new Map(S.map((s) => [s.subject_id, s.name]))
  const bySubject = new Map<string, { sum: number; observed: number; total: number }>()
  for (const c of C) {
    const e = bySubject.get(c.subject_id) ?? { sum: 0, observed: 0, total: 0 }
    e.total++
    const m = masteryById.get(c.concept_id)
    if (m) {
      e.sum += m.p
      e.observed++
    }
    bySubject.set(c.subject_id, e)
  }
  const subjectStats: SubjectMastery[] = [...bySubject.entries()]
    .filter(([, e]) => e.observed > 0)
    .map(([id, e]) => ({
      subjectId: id,
      subject: subjectName.get(id) ?? id,
      mastery: e.sum / e.observed,
      concepts: e.total,
      observed: e.observed,
    }))
    .sort((a, b) => a.mastery - b.mastery)

  // ---------- Weakest observed concepts ----------
  const weakest = M.map((m) => ({
    conceptId: m.concept_id,
    name: nameOf(m.concept_id),
    subjectId: conceptById.get(m.concept_id)?.subject_id ?? '',
    mastery: Number(m.mastery_prob),
    observations: Number(m.observation_count ?? 0),
  }))
    .sort((a, b) => a.mastery - b.mastery)
    .slice(0, 6)

  // BKT is unstable at low observation counts: with one or two attempts per
  // concept the estimate is close to "did you get that single question right".
  // Surface that rather than presenting a volatile number as settled.
  const obsCounts = M.map((m) => Number(m.observation_count ?? 0)).sort((a, b) => a - b)
  const medianObservations = obsCounts.length
    ? obsCounts[Math.floor(obsCounts.length / 2)]
    : 0

  const activeMinutes = SESS.reduce((a, s) => a + Number(s.active_minutes ?? 0), 0)

  return {
    attemptCount: A.length,
    hasEnoughForDiagnosis: A.length >= 5,
    rootCause,
    subjects: subjectStats,
    fixFirst,
    diagnosis,
    weakest,
    medianObservations,
    thinEstimate: medianObservations < 4,
    // Needs the Python fitter and ~5 tracked sessions. Null until then.
    focusHalfLife: null,
    sessionsTracked: SESS.length,
    activeMinutes,
    decayingCount: null,
  }
}