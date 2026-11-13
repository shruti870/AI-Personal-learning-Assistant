/**
 * Prompt for the AI tutor that explains a wrong answer (app/api/explain).
 * Pure, so it is unit-tested without calling the model.
 */

export const TUTOR_SYSTEM = `You are a patient tutor helping an Indian engineering student prepare for campus placement tests (aptitude, reasoning, DSA, DBMS, OS, computer networks).

The student just answered a multiple-choice question wrong. Explain it in at most 120 words, in plain text with no markdown, headings or bullet symbols, in three short paragraphs:
1. Why the option they chose is tempting, and exactly where that reasoning breaks.
2. The one idea that gets to the correct answer, with a tiny concrete example if it helps.
3. One quick self-check question they can answer in their head (do not give its answer).

If a named misconception is given, address it directly. If a weak prerequisite is given, say in one sentence that brushing up on it will make this topic easier. Use simple English. Never invent facts about the question that are not in it.`

export type TutorContext = {
  concept: string
  stem: string
  options: { body: string; isCorrect: boolean; chosen: boolean }[]
  misconception: { label: string; remediation: string | null } | null
  weakPrerequisite: { name: string; mastery: number } | null
}

export function buildTutorPrompt(c: TutorContext): string {
  const chosen = c.options.find((o) => o.chosen)
  const correct = c.options.find((o) => o.isCorrect)
  const lines = [
    `Concept: ${c.concept}`,
    `Question: ${c.stem}`,
    'Options:',
    ...c.options.map((o, i) => `  ${String.fromCharCode(65 + i)}. ${o.body}`),
    `Student chose: ${chosen?.body ?? 'unknown'}`,
    `Correct answer: ${correct?.body ?? 'unknown'}`,
  ]
  if (c.misconception) {
    lines.push(`Named misconception behind their choice: ${c.misconception.label}`)
    if (c.misconception.remediation) lines.push(`Teacher's note: ${c.misconception.remediation}`)
  }
  if (c.weakPrerequisite) {
    lines.push(
      `Weak prerequisite: ${c.weakPrerequisite.name} (mastery ${Math.round(
        c.weakPrerequisite.mastery * 100
      )}%)`
    )
  }
  return lines.join('\n')
}

/** How long after answering a wrong attempt can still be explained. */
export const EXPLAIN_WINDOW_MS = 30 * 60 * 1000

/** Why an attempt cannot be explained, or null when it can. */
export function explainRefusal(
  attempt: { is_correct: boolean; created_at: string } | null,
  now: number
): string | null {
  if (!attempt || attempt.is_correct || now - Date.parse(attempt.created_at) > EXPLAIN_WINDOW_MS) {
    return 'The tutor explains a wrong answer you gave in the last 30 minutes.'
  }
  return null
}

/**
 * Bounds model calls: one explanation per attempt (repeats are served from
 * memory) and a per-student cap over a sliding window. In-memory, so it is
 * per server instance; enough for a single-instance deployment.
 */
export class TutorLimiter {
  private explained = new Map<string, string>()
  private calls = new Map<string, number[]>()

  private readonly max: number
  private readonly windowMs: number

  // Plain fields, not parameter properties: node --test strips types only.
  constructor(max: number, windowMs: number) {
    this.max = max
    this.windowMs = windowMs
  }

  cached(userId: string, attemptId: string): string | undefined {
    return this.explained.get(`${userId}:${attemptId}`)
  }

  overLimit(userId: string, now: number): boolean {
    const recent = (this.calls.get(userId) ?? []).filter((t) => now - t < this.windowMs)
    this.calls.set(userId, recent)
    return recent.length >= this.max
  }

  record(userId: string, attemptId: string, explanation: string, now: number): void {
    this.explained.set(`${userId}:${attemptId}`, explanation)
    this.calls.set(userId, [...(this.calls.get(userId) ?? []), now])
  }
}
