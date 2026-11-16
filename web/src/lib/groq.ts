/**
 * Groq (free tier) as an alternative tutor backend. Used when GROQ_API_KEY is
 * set; otherwise the explain route calls Claude. Groq speaks the OpenAI chat
 * completions format, so this is a plain fetch, no extra package.
 */

export const GROQ_DEFAULT_MODEL = 'openai/gpt-oss-120b'

export type TutorReply =
  | { ok: true; text: string }
  | { ok: false; status: number; error: string }

export async function explainWithGroq(
  system: string,
  prompt: string,
  key: string,
  model = GROQ_DEFAULT_MODEL
): Promise<TutorReply> {
  let res: Response
  try {
    res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: prompt },
        ],
        max_completion_tokens: 2000,
        reasoning_effort: 'low', // short explanation, keep it quick
        include_reasoning: false,
      }),
      signal: AbortSignal.timeout(45_000),
    })
  } catch {
    return { ok: false, status: 502, error: 'Could not reach the AI tutor.' }
  }

  if (res.status === 401) {
    return { ok: false, status: 503, error: 'The AI tutor is not set up. Check GROQ_API_KEY in web/.env.local.' }
  }
  if (res.status === 429) {
    return { ok: false, status: 429, error: 'The tutor is busy. Try again in a minute.' }
  }
  if (!res.ok) return { ok: false, status: 502, error: `Tutor error (${res.status}).` }

  const data = (await res.json().catch(() => null)) as
    | { choices?: { message?: { content?: string | null } }[] }
    | null
  const text = data?.choices?.[0]?.message?.content?.trim()
  if (!text) return { ok: false, status: 502, error: 'Empty explanation.' }
  return { ok: true, text }
}
