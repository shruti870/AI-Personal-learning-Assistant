'use client'

import { Suspense, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import AuthShell from '@/components/AuthShell'

export default function LoginPage() {
  return (
    <Suspense fallback={null}>
      <LoginForm />
    </Suspense>
  )
}

function LoginForm() {
  const router = useRouter()
  const params = useSearchParams()
  const supabase = createClient()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(
    params.get('error') === 'confirmation_failed'
      ? 'That confirmation link is invalid or has expired. Try logging in, or sign up again.'
      : null
  )

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setBusy(true)

    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setBusy(false)

    if (error) {
      setError(
        error.message === 'Invalid login credentials'
          ? 'That email and password do not match an account.'
          : error.message
      )
      return
    }

    router.push(params.get('next') ?? '/dashboard')
    router.refresh()
  }

  return (
    <AuthShell
      eyebrow="LOG IN"
      title={<>Pick up where the model left off.</>}
      aside={<Aside />}
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        <label className="block">
          <span className="font-mono text-[10px] eyebrow text-faint">EMAIL</span>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            autoComplete="email"
            required
            className="mt-2 w-full bg-card border border-rule px-4 py-3 text-sm placeholder:text-faint focus:border-ink focus:outline-none transition-colors"
            placeholder="you@kiit.ac.in"
          />
        </label>

        <label className="block">
          <span className="font-mono text-[10px] eyebrow text-faint">PASSWORD</span>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
            required
            className="mt-2 w-full bg-card border border-rule px-4 py-3 text-sm placeholder:text-faint focus:border-ink focus:outline-none transition-colors"
            placeholder="Your password"
          />
        </label>

        {error && (
          <div className="border-l-2 border-alarm bg-alarm-wash px-4 py-3">
            <p className="font-mono text-[10px] eyebrow text-alarm mb-1">COULD NOT LOG IN</p>
            <p className="text-sm text-alarm">{error}</p>
          </div>
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full font-mono text-sm bg-ink text-paper py-3.5 hover:bg-blueprint transition-colors disabled:opacity-50"
        >
          {busy ? 'Checking\u2026' : 'Log in'}
        </button>
      </form>

      <p className="font-mono text-xs text-faint mt-7">
        No account yet?{' '}
        <Link href="/signup" className="text-ink border-b border-rule hover:border-ink">
          Create one
        </Link>
      </p>
    </AuthShell>
  )
}

function Aside() {
  return (
    <>
      <p className="font-mono text-[11px] eyebrow text-paper/50 mb-7">SINCE YOU WERE LAST HERE</p>
      <div className="space-y-px bg-paper/10 border border-paper/10">
        {[
          ['CONCEPTS DECAYING', '4', 'Retention dropped below 0.75 while you were away.'],
          ['OPEN ROOT CAUSES', '2', 'Still explaining most of your recent failures.'],
          ['PLAN STATUS', 'STALE', 'Regenerates the moment you log in.'],
        ].map(([label, value, note]) => (
          <div key={label} className="bg-ink px-6 py-5">
            <div className="flex items-baseline justify-between gap-4">
              <span className="font-mono text-[10px] eyebrow text-paper/50">{label}</span>
              <span className="font-display font-extrabold text-2xl text-amber tight">{value}</span>
            </div>
            <p className="text-sm text-paper/60 mt-1.5">{note}</p>
          </div>
        ))}
      </div>
      <p className="font-mono text-[10px] text-paper/40 mt-6">
        Sample figures. Yours load after login.
      </p>
    </>
  )
}