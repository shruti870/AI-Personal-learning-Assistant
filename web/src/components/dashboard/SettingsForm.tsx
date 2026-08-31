'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

const EXAMS = [
  { id: 'tcs_nqt', name: 'TCS NQT' },
  { id: 'infosys_se', name: 'Infosys SE' },
  { id: 'amazon_sde1', name: 'Amazon SDE-1' },
  { id: '', name: 'Semester exams only' },
]

const TRACKED = [
  ['Tab focus and blur', 'When the study tab loses focus, and for how long.'],
  ['Idle gaps', 'No input for 45 seconds or more during a block.'],
  ['Response times', 'How long each answer takes, against the item median.'],
  ['Hour of day', 'Which hours your accuracy is highest in.'],
]

const NOT_TRACKED = [
  'Keystrokes or what you type outside answer fields',
  'Which other tabs or sites are open',
  'Anything at all when tracking is off',
]

export default function SettingsForm({
  email,
  displayName,
  weeklyMinutes,
  trackingOptIn,
  targetExamId,
}: {
  email: string
  displayName: string
  weeklyMinutes: number
  trackingOptIn: boolean
  targetExamId: string | null
}) {
  const supabase = createClient()

  const [name, setName] = useState(displayName)
  const [minutes, setMinutes] = useState(weeklyMinutes)
  const [tracking, setTracking] = useState(trackingOptIn)
  const [exam, setExam] = useState(targetExamId ?? '')
  const [busy, setBusy] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save() {
    setBusy(true)
    setError(null)
    setSaved(false)

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return

    const { error } = await supabase
      .from('profiles')
      .update({
        display_name: name,
        weekly_minutes: minutes,
        tracking_opt_in: tracking,
        target_exam_id: exam || null,
      })
      .eq('student_id', user.id)

    setBusy(false)
    if (error) setError(error.message)
    else setSaved(true)
  }

  return (
    <div className="grid xl:grid-cols-12 gap-7">
      <div className="xl:col-span-7 space-y-7">
        <section className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">ACCOUNT</p>
          </div>
          <div className="px-6 py-6 space-y-5">
            <label className="block">
              <span className="font-mono text-[10px] eyebrow text-faint">DISPLAY NAME</span>
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="mt-2 w-full bg-paper border border-rule px-4 py-2.5 text-sm focus:border-ink focus:outline-none"
              />
            </label>
            <div>
              <span className="font-mono text-[10px] eyebrow text-faint">EMAIL</span>
              <p className="mt-2 font-mono text-sm text-soft">{email}</p>
            </div>
          </div>
        </section>

        <section className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">STUDY BUDGET</p>
          </div>
          <div className="px-6 py-6">
            <div className="flex items-baseline justify-between mb-3">
              <span className="font-mono text-xs">Minutes per week</span>
              <span className="font-display font-extrabold text-2xl tight">{minutes}</span>
            </div>
            <input
              type="range"
              min={60}
              max={1200}
              step={30}
              value={minutes}
              onChange={(e) => setMinutes(Number(e.target.value))}
              className="w-full accent-[#141A17]"
            />
            <p className="text-xs text-soft mt-3 leading-relaxed">
              The planner will not fill this if it cannot justify the time. Setting it
              high does not produce a busier plan, only a longer ceiling.
            </p>
          </div>
        </section>

        <section className="border border-rule bg-card">
          <div className="border-b border-rule px-6 py-3">
            <p className="font-mono text-[10px] eyebrow text-faint">TARGET</p>
          </div>
          <div className="px-6 py-6">
            <div className="grid sm:grid-cols-2 gap-2">
              {EXAMS.map((e) => (
                <button
                  key={e.id || 'none'}
                  onClick={() => setExam(e.id)}
                  className={`font-mono text-xs px-4 py-3 border text-left transition-colors ${
                    exam === e.id
                      ? 'border-ink bg-ink text-paper'
                      : 'border-rule text-soft hover:border-ink hover:text-ink'
                  }`}
                >
                  {e.name}
                </button>
              ))}
            </div>
            <p className="text-xs text-soft mt-4 leading-relaxed">
              Changes topic weights in the planner. Your mastery estimates are unaffected.
            </p>
          </div>
        </section>
      </div>

      <div className="xl:col-span-5 space-y-7">
        <section
          className={`border-2 ${tracking ? 'border-blueprint' : 'border-rule'} bg-card`}
        >
          <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
            <p className="font-mono text-[10px] eyebrow text-faint">ATTENTION TRACKING</p>
            <button
              onClick={() => setTracking(!tracking)}
              role="switch"
              aria-checked={tracking}
              className={`font-mono text-[10px] px-3 py-1.5 border transition-colors ${
                tracking
                  ? 'border-blueprint bg-blueprint text-paper'
                  : 'border-rule text-faint hover:border-ink hover:text-ink'
              }`}
            >
              {tracking ? 'ON' : 'OFF'}
            </button>
          </div>

          <div className="px-5 py-5">
            <p className="font-mono text-[10px] eyebrow text-faint mb-3">WHAT IS RECORDED</p>
            <ul className="space-y-3 mb-6">
              {TRACKED.map(([k, v]) => (
                <li key={k}>
                  <p className="font-mono text-[11px]">{k}</p>
                  <p className="text-xs text-soft mt-0.5 leading-relaxed">{v}</p>
                </li>
              ))}
            </ul>

            <p className="font-mono text-[10px] eyebrow text-faint mb-3">WHAT IS NOT</p>
            <ul className="space-y-1.5">
              {NOT_TRACKED.map((n) => (
                <li key={n} className="text-xs text-soft leading-relaxed">
                  {n}
                </li>
              ))}
            </ul>

            {!tracking && (
              <div className="border-l-2 border-amber bg-amber-wash px-4 py-3 mt-5">
                <p className="text-xs text-soft leading-relaxed">
                  With this off, blocks default to 25 minutes for everyone and the
                  focus half-life stays unmeasured.
                </p>
              </div>
            )}
          </div>
        </section>

        <div className="flex flex-wrap items-center gap-4">
          <button
            onClick={save}
            disabled={busy}
            className="font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors disabled:opacity-50"
          >
            {busy ? 'Saving\u2026' : 'Save changes'}
          </button>
          {saved && <span className="font-mono text-xs text-mastery">Saved</span>}
          {error && <span className="font-mono text-xs text-alarm">{error}</span>}
        </div>
      </div>
    </div>
  )
}