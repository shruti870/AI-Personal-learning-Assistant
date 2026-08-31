import Link from 'next/link'

export default function CallToAction() {
  return (
    <section className="rule bg-ink text-paper">
      <div className="mx-auto max-w-6xl px-6 py-24 text-center">
        <p className="font-mono text-[11px] eyebrow text-paper/50 mb-7">TWENTY QUESTIONS, TWELVE MINUTES</p>
        <h2 className="font-display font-extrabold text-3xl md:text-5xl tight leading-tight max-w-3xl mx-auto">
          Find out what you&rsquo;re<br />confidently wrong about.
        </h2>
        <p className="mt-7 text-paper/70 max-w-lg mx-auto leading-relaxed">
          The placement test maps you onto the concept graph and generates your first week.
          No score at the end &mdash; a diagnosis.
        </p>
        <Link
          href="/signup"
          className="inline-block mt-10 font-mono text-sm bg-paper text-ink px-8 py-4 hover:bg-amber hover:text-paper transition-colors"
        >
          Start the test
        </Link>
      </div>
    </section>
  )
}