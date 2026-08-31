import { createClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'

/**
 * Grading runs server-side because the browser must never see is_correct
 * before answering. The client sends what it chose; the server decides.
 * The Postgres trigger on `attempts` then updates mastery automatically.
 */
export async function POST(request: Request) {
  const supabase = await createClient()

  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 })
  }

  const body = await request.json()
  const { questionId, optionId, confidence, timeTakenSec, sessionId, minutesIntoSession } = body

  if (!questionId || !optionId || !confidence) {
    return NextResponse.json({ error: 'Missing fields' }, { status: 400 })
  }

  const { data: option } = await supabase
    .from('options')
    .select('option_id, question_id, is_correct, misconception_id')
    .eq('option_id', optionId)
    .single()

  if (!option || option.question_id !== questionId) {
    return NextResponse.json({ error: 'Unknown option' }, { status: 400 })
  }

  const { data: question } = await supabase
    .from('questions')
    .select('median_time_sec, primary_concept_id')
    .eq('question_id', questionId)
    .single()

  const median = question?.median_time_sec ?? 45
  const ratio = timeTakenSec / median

  // Rule-based error typing. Replaced by a fitted classifier once
  // several hundred hand-labelled attempts exist.
  let errorType: string
  if (ratio < 0.2) {
    errorType = option.is_correct ? 'guess' : 'careless'
  } else if (option.is_correct) {
    errorType = confidence === 3 ? 'mastered' : 'uncertain_correct'
  } else if (option.misconception_id) {
    errorType = 'misconception'
  } else {
    errorType = 'procedural_slip'
  }

  const { error } = await supabase.from('attempts').insert({
    student_id: user.id,
    question_id: questionId,
    chosen_option_id: optionId,
    session_id: sessionId ?? null,
    is_correct: option.is_correct,
    confidence,
    time_taken_sec: Math.round(timeTakenSec),
    minutes_into_session: minutesIntoSession ?? null,
    error_type: errorType,
  })

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  let misconception = null
  if (option.misconception_id) {
    const { data: m } = await supabase
      .from('misconceptions')
      .select('label, remediation_note')
      .eq('misconception_id', option.misconception_id)
      .single()
    misconception = m
  }

  const { data: correctOption } = await supabase
    .from('options')
    .select('body')
    .eq('question_id', questionId)
    .eq('is_correct', true)
    .single()

  return NextResponse.json({
    isCorrect: option.is_correct,
    errorType,
    misconception,
    correctAnswer: correctOption?.body ?? null,
    concept: question?.primary_concept_id ?? null,
  })
}