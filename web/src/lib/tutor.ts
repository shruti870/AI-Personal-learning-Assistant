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
