import Link from 'next/link'

export default function SiteFooter() {
  return (
    <footer>
      <div className="mx-auto max-w-6xl px-6 py-12 flex flex-wrap items-center justify-between gap-6 font-mono text-xs text-faint">
        <div className="flex items-baseline gap-3">
          <span className="font-display font-extrabold text-sm text-ink tight">DIAGNOSTIC</span>
          <span>Major project &middot; KIIT &middot; Group 82</span>
        </div>
        <div className="flex gap-7">
          <Link href="/privacy" className="hover:text-ink">Attention tracking &amp; privacy</Link>
          <Link href="/sources" className="hover:text-ink">Content sources</Link>
        </div>
      </div>
    </footer>
  )
}