'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import AuthShell from '@/components/AuthShell'

export default function SignupPage() {
  const router = useRouter()
  const supabase = createClient()

  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [sent, setSent] = useState(false)

  const weak = password.length > 0 && password.length < 8

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)

    if (password.length < 8) {
      setError('Password must be at least 8 characters.')
      return
    }

    setBusy(true)
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { display_name: name },
        emailRedirectTo: `${location.origin}/auth/callback`,
      },
    })
    setBusy(false)

    if (error) {
      setError(error.message)
      return
    }

    // If email confirmation is on, there is no session yet.
    if (data.session) {
      router.push('/dashboard')
      router.refresh()
    } else {
      setSent(true)
    }
  }

  if (sent) {
    return (
      <AuthShell
        eyebrow="CHECK YOUR EMAIL"
        title={<>One more step.</>}
        aside={<Aside />}
      >
        <p className="text-soft leading-relaxed">
          We sent a confirmation link to <span className="text-ink">{email}</span>.
          Open it and you will land straight on your placement test.
        </p>
        <p className="font-mono text-xs text-faint mt-6">
          Nothing arrived? Check spam, then{' '}
          <button
            onClick={() => setSent(false)}
            className="text-ink border-b border-rule hover:border-ink"
          >
            try a different address
          </button>
          .
        </p>
      </AuthShell>
    )
  }

  return (
    <AuthShell
      eyebrow="CREATE ACCOUNT"
      title={<>Find out what you&rsquo;re confidently wrong about.</>}
      aside={<Aside />}
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        <Field
          label="NAME"
          type="text"
          value={name}
          onChange={setName}
          placeholder="Your name"
          autoComplete="name"
          required
        />
        <Field
          label="EMAIL"
          type="email"
          value={email}
          onChange={setEmail}
          placeholder="you@kiit.ac.in"
          autoComplete="email"
          required
        />
        <div>
          <Field
            label="PASSWORD"
            type="password"
            value={password}
            onChange={setPassword}
            placeholder="At least 8 characters"
            autoComplete="new-password"
            required
          />
          {weak && (
            <p className="font-mono text-[10px] text-amber mt-2">
              {8 - password.length} more character{8 - password.length === 1 ? '' : 's'} needed
            </p>
          )}
        </div>

        {error && (
          <div className="border-l-2 border-alarm bg-alarm-wash px-4 py-3">
            <p className="font-mono text-[10px] eyebrow text-alarm mb-1">COULD NOT SIGN UP</p>
            <p className="text-sm text-alarm">{error}</p>
          </div>
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full font-mono text-sm bg-ink text-paper py-3.5 hover:bg-blueprint transition-colors disabled:opacity-50"
        >
          {busy ? 'Creating account\u2026' : 'Create account'}
        </button>
      </form>

      <p className="font-mono text-xs text-faint mt-7">
        Already have one?{' '}
        <Link href="/login" className="text-ink border-b border-rule hover:border-ink">
          Log in
        </Link>
      </p>
    </AuthShell>
  )
}

function Aside() {
  return (
    <>
      <p className="font-mono text-[11px] eyebrow text-paper/50 mb-6">WHAT HAPPENS NEXT</p>
      <ol className="space-y-6">
        {[
          ['01', 'Twenty questions, twelve minutes', 'Adaptive, spread across the concept graph. Confidence declared before each answer.'],
          ['02', 'A diagnosis, not a score', 'Which beliefs are wrong, which answers you guessed, and the root concepts underneath both.'],
          ['03', 'Week one, generated', 'Blocks sized to your attention span, ordered so nothing arrives before its prerequisites.'],
        ].map(([n, h, b]) => (
          <li key={n} className="flex gap-5">
            <span className="font-mono text-xs text-amber pt-1">{n}</span>
            <div>
              <p className="font-display font-semibold text-lg tight">{h}</p>
              <p className="text-sm text-paper/60 mt-1.5 leading-relaxed">{b}</p>
            </div>
          </li>
        ))}
      </ol>
    </>
  )
}

function Field({
  label,
  type,
  value,
  onChange,
  placeholder,
  autoComplete,
  required,
}: {
  label: string
  type: string
  value: string
  onChange: (v: string) => void
  placeholder?: string
  autoComplete?: string
  required?: boolean
}) {
  return (
    <label className="block">
      <span className="font-mono text-[10px] eyebrow text-faint">{label}</span>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        autoComplete={autoComplete}
        required={required}
        className="mt-2 w-full bg-card border border-rule px-4 py-3 text-sm placeholder:text-faint focus:border-ink focus:outline-none transition-colors"
      />
    </label>
  )
}