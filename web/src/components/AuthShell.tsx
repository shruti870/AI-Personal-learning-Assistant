import Link from 'next/link'

export default function AuthShell({
  eyebrow,
  title,
  children,
  aside,
}: {
  eyebrow: string
  title: React.ReactNode
  children: React.ReactNode
  aside: React.ReactNode
}) {
  return (
    <div className="min-h-screen grid lg:grid-cols-2">
      {/* Form side */}
      <div className="flex flex-col px-6 py-10 sm:px-12 lg:px-16">
        <Link href="/" className="font-display font-extrabold text-lg tight w-fit">
          DIAGNOSTIC
        </Link>

        <div className="flex-1 flex items-center">
          <div className="w-full max-w-sm py-12">
            <p className="font-mono text-[11px] eyebrow text-blueprint mb-5">{eyebrow}</p>
            <h1 className="font-display font-extrabold text-3xl sm:text-4xl tight leading-[1.1] mb-9">
              {title}
            </h1>
            {children}
          </div>
        </div>

        <p className="font-mono text-[10px] text-faint">
          Major project &middot; KIIT &middot; Group 82
        </p>
      </div>

      {/* Context side */}
      <div className="hidden lg:flex bg-ink text-paper items-center px-16">
        <div className="max-w-md">{aside}</div>
      </div>
    </div>
  )
}