export default function PageHead({
  eyebrow,
  title,
  lede,
  aside,
}: {
  eyebrow: string
  title: string
  lede: string
  aside?: React.ReactNode
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-6 mb-8">
      <div>
        <p className="font-mono text-[11px] eyebrow text-faint mb-4">{eyebrow}</p>
        <h1 className="font-display font-extrabold text-3xl tight leading-tight">{title}</h1>
        <p className="mt-3 text-soft leading-relaxed max-w-xl">{lede}</p>
      </div>
      {aside}
    </div>
  )
}