import Link from 'next/link'

export default function SiteNav() {
  return (
    <header className="border-b border-rule bg-paper/90 backdrop-blur sticky top-0 z-50">
      <div className="mx-auto max-w-6xl px-6 h-16 flex items-center justify-between">
        <div className="flex items-baseline gap-3">
          <span className="font-display font-extrabold text-lg tight">DIAGNOSTIC</span>
          <span className="font-mono text-[10px] text-faint eyebrow hidden sm:inline">
            ADAPTIVE LEARNING ENGINE
          </span>
        </div>
        <nav className="flex items-center gap-7 font-mono text-xs">
          <Link href="#how" className="hidden sm:inline text-soft hover:text-ink">How it works</Link>
          <Link href="#test" className="hidden sm:inline text-soft hover:text-ink">Try one</Link>
          <Link href="#focus" className="hidden sm:inline text-soft hover:text-ink">Attention</Link>
          <Link href="#exams" className="hidden md:inline text-soft hover:text-ink">Placements</Link>
          <Link
            href="/signup"
            className="border border-ink px-4 py-2 hover:bg-ink hover:text-paper transition-colors"
          >
            Start
          </Link>
        </nav>
      </div>
    </header>
  )
}