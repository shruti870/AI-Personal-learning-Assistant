'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'

const NAV = [
  { href: '/dashboard', label: 'Today' },
  { href: '/study', label: 'Study' },
  { href: '/dashboard/diagnosis', label: 'Diagnosis' },
  { href: '/dashboard/map', label: 'Concept map' },
  { href: '/dashboard/plan', label: 'Plan' },
  { href: '/dashboard/simulate', label: 'Simulate' },
  { href: '/dashboard/settings', label: 'Settings' },
]

export default function SideRail({ name }: { name: string }) {
  const path = usePathname()

  return (
    <aside className="lg:fixed lg:inset-y-0 lg:left-0 lg:w-56 bg-ink text-paper flex lg:flex-col z-40">
      <div className="px-6 py-5 lg:py-6 shrink-0">
        <Link href="/" className="font-display font-extrabold text-base tight">
          DIAGNOSTIC
        </Link>
      </div>

      <nav className="flex lg:flex-col gap-px overflow-x-auto lg:overflow-visible lg:mt-2 flex-1">
        {NAV.map((item) => {
          const active =
            item.href === '/study'
              ? path.startsWith('/study')
              : path === item.href
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`font-mono text-xs px-6 py-3 whitespace-nowrap transition-colors ${
                active
                  ? 'bg-paper/10 text-paper border-l-2 border-amber'
                  : 'text-paper/50 hover:text-paper hover:bg-paper/5 border-l-2 border-transparent'
              }`}
            >
              {item.label}
            </Link>
          )
        })}
      </nav>

      <div className="hidden lg:block px-6 py-6 border-t border-paper/10">
        <p className="font-mono text-[10px] eyebrow text-paper/40 mb-1.5">SIGNED IN</p>
        <p className="font-mono text-xs text-paper/80 truncate">{name}</p>
        <Link
          href="/dashboard/settings"
          className="font-mono text-[10px] text-paper/40 hover:text-paper mt-3 inline-block"
        >
          Settings
        </Link>
      </div>
    </aside>
  )
}