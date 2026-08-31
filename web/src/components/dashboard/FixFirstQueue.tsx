import Link from 'next/link'
import type { FixItem } from '@/lib/analytics'

export default function FixFirstQueue({ items }: { items: FixItem[] }) {
  return (
    <div className="border border-rule bg-card">
      <div className="border-b border-rule px-5 py-3 flex items-center justify-between">
        <p className="font-mono text-[10px] eyebrow text-faint">FIX FIRST</p>
        <span className="font-mono text-[10px] text-faint">NAMED BELIEFS</span>
      </div>
      {items.length === 0 ? (
        <div className="px-5 py-5">
          <p className="text-xs text-soft leading-relaxed">
            No diagnosed misconceptions yet. These appear when a wrong answer matches a
            distractor tagged to a specific false belief.
          </p>
        </div>
      ) : (
        <ol className="divide-y divide-rule">
          {items.map((it, i) => (
            <li key={it.belief} className="px-5 py-4">
              <div className="flex items-baseline justify-between gap-3 mb-1.5">
                <Link
                  href={`/study/session?concept=${encodeURIComponent(it.conceptId)}`}
                  className="font-mono text-[11px] truncate hover:text-blueprint"
                >
                  <span className="text-faint mr-2">{String(i + 1).padStart(2, '0')}</span>
                  {it.concept}
                </Link>
                <span className="font-mono text-[10px] text-amber shrink-0">
                  {it.times}x
                </span>
              </div>
              <p className="text-xs text-soft leading-relaxed">{it.belief}</p>
              <p className="font-mono text-[10px] text-faint mt-1.5">{it.subject}</p>
            </li>
          ))}
        </ol>
      )}
    </div>
  )
}