import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildTutorPrompt, explainRefusal, TUTOR_SYSTEM, TutorLimiter } from './tutor.ts'

const base = {
  concept: 'Third normal form',
  stem: 'Which normal form removes transitive dependencies?',
  options: [
    { body: '2NF', isCorrect: false, chosen: true },
    { body: '3NF', isCorrect: true, chosen: false },
    { body: 'BCNF', isCorrect: false, chosen: false },
  ],
  misconception: null,
  weakPrerequisite: null,
}

test('names the question, the chosen option and the correct one', () => {
  const p = buildTutorPrompt(base)
  assert.match(p, /Which normal form removes transitive dependencies\?/)
  assert.match(p, /Student chose: 2NF/)
  assert.match(p, /Correct answer: 3NF/)
  assert.match(p, /Concept: Third normal form/)
})

test('includes the named misconception and the weak prerequisite when known', () => {
  const p = buildTutorPrompt({
    ...base,
    misconception: { label: 'confuses 2NF with 3NF', remediation: 'Partial vs transitive.' },
    weakPrerequisite: { name: 'Functional dependency', mastery: 0.31 },
  })
  assert.match(p, /confuses 2NF with 3NF/)
  assert.match(p, /Partial vs transitive\./)
  assert.match(p, /Functional dependency \(mastery 31%\)/)
})

test('leaves the optional sections out when there is nothing to say', () => {
  const p = buildTutorPrompt(base)
  assert.doesNotMatch(p, /misconception/i)
  assert.doesNotMatch(p, /prerequisite/i)
})

test('the system prompt is fixed text, so it never varies between requests', () => {
  assert.equal(typeof TUTOR_SYSTEM, 'string')
  assert.doesNotMatch(TUTOR_SYSTEM, /\$\{/)
})

const NOW = Date.parse('2026-11-12T10:00:00Z')
const minutesAgo = (m: number) => new Date(NOW - m * 60_000).toISOString()

test('only a recent wrong attempt can be explained', () => {
  assert.ok(explainRefusal(null, NOW))
  assert.ok(explainRefusal({ is_correct: true, created_at: minutesAgo(1) }, NOW))
  assert.ok(explainRefusal({ is_correct: false, created_at: minutesAgo(31) }, NOW))
  assert.equal(explainRefusal({ is_correct: false, created_at: minutesAgo(29) }, NOW), null)
})

test('a repeat request for the same attempt gets the saved explanation', () => {
  const l = new TutorLimiter(20, 60 * 60_000)
  assert.equal(l.cached('u1', 'a1'), undefined)
  l.record('u1', 'a1', 'because…', NOW)
  assert.equal(l.cached('u1', 'a1'), 'because…')
  assert.equal(l.cached('u2', 'a1'), undefined)
})

test('each student is capped per hour, and the window slides', () => {
  const l = new TutorLimiter(2, 60 * 60_000)
  l.record('u1', 'a1', 'x', NOW)
  l.record('u1', 'a2', 'x', NOW)
  assert.equal(l.overLimit('u1', NOW), true)
  assert.equal(l.overLimit('u2', NOW), false)
  assert.equal(l.overLimit('u1', NOW + 61 * 60_000), false)
})
