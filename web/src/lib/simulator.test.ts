import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  buildSubjects,
  projectedMastery,
  readiness,
  bestNextHour,
  PRIOR,
} from './simulator.ts'

const concepts = [
  { concept_id: 'dsa.arrays', subject_id: 'dsa' },
  { concept_id: 'dsa.graphs', subject_id: 'dsa' },
  { concept_id: 'apt.ratio', subject_id: 'apt' },
]
const names = [
  { subject_id: 'dsa', name: 'DSA' },
  { subject_id: 'apt', name: 'Aptitude' },
]

test('subject mastery averages every concept, unseen ones at the prior', () => {
  const s = buildSubjects({
    concepts,
    subjects: names,
    mastery: [{ concept_id: 'dsa.arrays', mastery_prob: 0.75 }],
    examWeights: [],
  })
  const dsa = s.find((x) => x.id === 'dsa')!
  assert.equal(dsa.mastery, (0.75 + PRIOR) / 2)
  assert.equal(dsa.observed, 1)
  assert.equal(dsa.concepts, 2)
  assert.equal(s.find((x) => x.id === 'apt')!.mastery, PRIOR)
})

test('without a target exam every subject weighs the same', () => {
  const s = buildSubjects({ concepts, subjects: names, mastery: [], examWeights: [] })
  assert.deepEqual(s.map((x) => x.weight), [0.5, 0.5])
})

test('exam weights are averaged per subject and normalised to sum to 1', () => {
  const s = buildSubjects({
    concepts,
    subjects: names,
    mastery: [],
    examWeights: [
      { concept_id: 'dsa.arrays', weight: 1.8 },
      { concept_id: 'dsa.graphs', weight: 1.8 },
      { concept_id: 'apt.ratio', weight: 0.6 },
    ],
  })
  assert.equal(s.find((x) => x.id === 'dsa')!.weight, 0.75)
  assert.equal(s.find((x) => x.id === 'apt')!.weight, 0.25)
})

test('gains saturate: the second hour adds less than the first', () => {
  const s = { id: 'x', name: 'X', mastery: 0.3, weight: 1, concepts: 1, observed: 1 }
  const first = projectedMastery(s, 1) - projectedMastery(s, 0)
  const second = projectedMastery(s, 2) - projectedMastery(s, 1)
  assert.equal(projectedMastery(s, 0), 0.3)
  assert.ok(first > second && second > 0)
  assert.ok(projectedMastery(s, 1000) <= 0.98)
})

test('best next hour goes to the weak, heavily weighted subject', () => {
  const subjects = [
    { id: 'weak', name: 'Weak', mastery: 0.2, weight: 0.7, concepts: 1, observed: 1 },
    { id: 'strong', name: 'Strong', mastery: 0.9, weight: 0.3, concepts: 1, observed: 1 },
  ]
  assert.equal(bestNextHour(subjects, {})!.id, 'weak')
  assert.ok(readiness(subjects, { weak: 3 }) > readiness(subjects, {}))
})
