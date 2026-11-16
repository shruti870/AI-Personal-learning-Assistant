import Anthropic from '@anthropic-ai/sdk'
import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import {
  buildTutorPrompt,
  explainRefusal,
  TUTOR_SYSTEM,
  TutorLimiter,
  type TutorContext,
} from '@/lib/tutor'
import { type Embed, one } from '@/lib/supabase/embed'

/**
 * AI tutor: explains the student's most recent WRONG answer to a question.
 *
 * Only explains an attempt the student actually made in the last 30 minutes,
 * once per attempt, and at most 20 times an hour per student, so the route
 * cannot be used as a general-purpose chatbot on our API key.
 * The correct answer is read here on the server, after the attempt is
 * recorded, so nothing leaks before answering.
 */
export const maxDuration = 60

const MODEL = 'claude-opus-5-5'
const limiter = new TutorLimiter(20, 60 * 60 * 1000)

type OptionRow = {
  option_id: string
  body: string
  is_correct: boolean
  ordinal: number
  misconceptions: Embed<{ label: string; remediation_note: string | null }>
}

export async function POST(request: Request) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Not signed in' }, { status: 401 })

  const { questionId } = await request.json().catch(() => ({}))
  if (!questionId) return NextResponse.json({ error: 'Missing questionId' }, { status: 400 })

  // The answer key (is_correct, misconception_id) is service-role only.
  let admin: ReturnType<typeof createAdminClient>
  try {
    admin = createAdminClient()
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 500 })
  }

  const [{ data: attempt }, { data: question }] = await Promise.all([
    supabase
      .from('attempts')
      .select('attempt_id, chosen_option_id, is_correct, created_at')
      .eq('student_id', user.id)
      .eq('question_id', questionId)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    admin
      .from('questions')
      .select(`
        stem, primary_concept_id,
        concepts:primary_concept_id ( name ),
        options ( option_id, body, is_correct, ordinal,
          misconceptions:misconception_id ( label, remediation_note ) )
      `)
      .eq('question_id', questionId)
      .single(),
  ])

  const refusal = explainRefusal(attempt, Date.now())
  if (refusal || !attempt) {
    return NextResponse.json({ error: refusal }, { status: 400 })
  }
  const saved = limiter.cached(user.id, attempt.attempt_id)
  if (saved) return NextResponse.json({ explanation: saved })
  if (limiter.overLimit(user.id, Date.now())) {
    return NextResponse.json(
      { error: 'You have used the tutor a lot this hour. Try again later.' },
      { status: 429 }
    )
  }

  if (!question) return NextResponse.json({ error: 'Unknown question' }, { status: 404 })

  const options = ((question.options ?? []) as unknown as OptionRow[]).sort(
    (a, b) => a.ordinal - b.ordinal
  )
  const chosen = options.find((o) => o.option_id === attempt.chosen_option_id)
  const mc = one(chosen?.misconceptions)

  // Weakest prerequisite the student has actually been measured on.
  const { data: parents } = await supabase
    .from('prerequisites')
    .select('parent_id, concepts:parent_id ( name )')
    .eq('child_id', question.primary_concept_id)
  let weakPrerequisite: TutorContext['weakPrerequisite'] = null
  if (parents && parents.length) {
    const { data: pm } = await supabase
      .from('mastery')
      .select('concept_id, mastery_prob')
      .eq('student_id', user.id)
      .in('concept_id', parents.map((p) => p.parent_id))
    const weakest = (pm ?? [])
      .map((m) => ({ id: m.concept_id, mastery: Number(m.mastery_prob) }))
      .filter((m) => m.mastery < 0.6)
      .sort((a, b) => a.mastery - b.mastery)[0]
    if (weakest) {
      const p = parents.find((x) => x.parent_id === weakest.id)
      weakPrerequisite = {
        name: one(p?.concepts as Embed<{ name: string }>)?.name ?? weakest.id,
        mastery: weakest.mastery,
      }
    }
  }

  const prompt = buildTutorPrompt({
    concept:
      one(question.concepts as Embed<{ name: string }>)?.name ??
      question.primary_concept_id,
    stem: question.stem,
    options: options.map((o) => ({
      body: o.body,
      isCorrect: o.is_correct,
      chosen: o.option_id === attempt.chosen_option_id,
    })),
    misconception: mc ? { label: mc.label, remediation: mc.remediation_note } : null,
    weakPrerequisite,
  })

  try {
    const client = new Anthropic()
    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 2000,
      // Short explanation: low effort keeps it quick and cheap.
      output_config: { effort: 'low' },
      // If the model declines, the API retries on a fallback model in the same call.
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      system: TUTOR_SYSTEM,
      messages: [{ role: 'user', content: prompt }],
    })

    if (response.stop_reason === 'refusal') {
      return NextResponse.json(
        { error: 'The tutor could not explain this one. Try the teacher note above.' },
        { status: 502 }
      )
    }
    const text = response.content
      .flatMap((b) => (b.type === 'text' ? [b.text] : []))
      .join('\n')
      .trim()
    if (!text) return NextResponse.json({ error: 'Empty explanation.' }, { status: 502 })
    limiter.record(user.id, attempt.attempt_id, text, Date.now())
    return NextResponse.json({ explanation: text })
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) {
      return NextResponse.json(
        { error: 'The AI tutor is not set up. Add ANTHROPIC_API_KEY to web/.env.local.' },
        { status: 503 }
      )
    }
    if (error instanceof Anthropic.RateLimitError) {
      return NextResponse.json({ error: 'The tutor is busy. Try again in a minute.' }, { status: 429 })
    }
    if (error instanceof Anthropic.APIConnectionError) {
      return NextResponse.json({ error: 'Could not reach the AI tutor.' }, { status: 502 })
    }
    if (error instanceof Anthropic.APIError) {
      return NextResponse.json({ error: `Tutor error (${error.status}).` }, { status: 502 })
    }
    // The SDK throws a plain Error when it finds no credentials at all.
    return NextResponse.json(
      { error: 'The AI tutor is unavailable. Is ANTHROPIC_API_KEY set in web/.env.local?' },
      { status: 503 }
    )
  }
}
