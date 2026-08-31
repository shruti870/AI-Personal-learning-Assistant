export default function TheGap() {
  return (
    <section className="rule">
      <div className="mx-auto max-w-6xl px-6 py-20">
        <div className="grid md:grid-cols-12 gap-10">
          <div className="md:col-span-3">
            <p className="font-mono text-[11px] eyebrow text-faint">THE GAP</p>
          </div>
          <div className="md:col-span-9">
            <p className="font-display font-semibold text-2xl md:text-[2rem] leading-snug tight max-w-3xl">
              A quiz app knows you scored 6 out of 10. It doesn&rsquo;t know that four of those
              wrong answers came from one belief you&rsquo;ve held since second year.
            </p>
            <p className="mt-6 text-soft max-w-2xl leading-relaxed">
              Binary right-and-wrong throws away almost everything useful. Which wrong option you
              picked, how sure you were, how long you took, and what you already knew going in
              &mdash; all of it is signal, and all of it usually gets discarded.
            </p>
          </div>
        </div>
      </div>
    </section>
  )
}