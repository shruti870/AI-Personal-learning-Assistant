import Link from 'next/link'

export default function EmptyState({
  title,
  body,
  cta = 'Take the placement test',
  href = '/study/placement',
}: {
  title: string
  body: string
  cta?: string
  href?: string
}) {
  return (
    <div className="border border-rule bg-card px-6 py-10 text-center">
      <p className="font-display font-semibold text-lg tight">{title}</p>
      <p className="text-sm text-soft mt-3 max-w-md mx-auto leading-relaxed">{body}</p>
      <Link
        href={href}
        className="inline-block mt-6 font-mono text-xs border border-ink px-5 py-2.5 hover:bg-ink hover:text-paper transition-colors"
      >
        {cta}
      </Link>
    </div>
  )
}