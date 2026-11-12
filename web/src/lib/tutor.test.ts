import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildTutorPrompt, TUTOR_SYSTEM } from './tutor.ts'

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
