import Link from 'next/link'

export default function Hero() {
  return (
    <section className="mx-auto max-w-6xl px-6 pt-16 pb-20 md:pt-24 md:pb-28">
      <div className="grid md:grid-cols-12 gap-12 items-center">
        <div className="md:col-span-6">
          <p className="font-mono text-[11px] eyebrow text-blueprint mb-6">ROOT-CAUSE DIAGNOSIS</p>
          <h1 className="font-display font-extrabold tight text-4xl sm:text-5xl lg:text-[3.4rem] leading-[1.05]">
            You&rsquo;re not bad at<br />Dijkstra. You&rsquo;re bad<br />at sorting.
          </h1>
          <p className="mt-7 text-lg text-soft max-w-md leading-relaxed">
            Most study apps flag the topic you failed. This one traces the failure down your
            prerequisite graph and names the concept that actually caused it.
          </p>
          <div className="mt-9 flex flex-wrap items-center gap-4">
            <Link
              href="/signup"
              className="font-mono text-sm bg-ink text-paper px-7 py-3.5 hover:bg-blueprint transition-colors"
            >
              Take the placement test
            </Link>
            <Link
              href="#how"
              className="font-mono text-sm text-soft border-b border-rule pb-0.5 hover:text-ink hover:border-ink"
            >
              See how it works
            </Link>
          </div>
        </div>

        <div className="md:col-span-6">
          <div className="border border-rule bg-card p-6">
            <div className="flex items-center justify-between mb-5">
              <span className="font-mono text-[10px] eyebrow text-faint">LIVE TRACE &mdash; ATTEMPT #4127</span>
              <span className="font-mono text-[10px] text-alarm">6 / 8 FAILED</span>
            </div>
            <BlameTrace />
          </div>
        </div>
      </div>
    </section>
  )
}

function BlameTrace() {
  return (
    <svg
      viewBox="0 0 420 330"
      className="w-full"
      role="img"
      aria-label="A failure on Dijkstra distributing blame to three prerequisites, with sorting basics identified as the root cause."
    >
      <g className="trace-node d1">
        <rect x="130" y="8" width="160" height="52" fill="#F6E5E4" stroke="#9E2B2B" strokeWidth="1" />
        <text x="210" y="30" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="13" fill="#9E2B2B">Dijkstra</text>
        <text x="210" y="47" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#9E2B2B">failed</text>
      </g>

      <line className="trace-edge d2" x1="180" y1="60" x2="72" y2="112" stroke="#7C877F" strokeWidth="1" />
      <line className="trace-edge d2" x1="210" y1="60" x2="210" y2="112" stroke="#B8721A" strokeWidth="2" />
      <line className="trace-edge d2" x1="240" y1="60" x2="348" y2="112" stroke="#7C877F" strokeWidth="1" />

      <g className="trace-node d3">
        <rect x="8" y="114" width="128" height="52" fill="#FBFBF8" stroke="#C8D2C7" />
        <text x="72" y="136" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#4A554E">Adjacency list</text>
        <text x="72" y="153" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#7C877F">blame 18%</text>
      </g>
      <g className="trace-node d3">
        <rect x="146" y="114" width="128" height="52" fill="#FBFBF8" stroke="#B8721A" />
        <text x="210" y="136" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#141A17">Priority queue</text>
        <text x="210" y="153" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#B8721A">blame 62%</text>
      </g>
      <g className="trace-node d3">
        <rect x="284" y="114" width="128" height="52" fill="#FBFBF8" stroke="#C8D2C7" />
        <text x="348" y="136" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#4A554E">BFS traversal</text>
        <text x="348" y="153" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#7C877F">blame 20%</text>
      </g>

      <line className="trace-edge d4" x1="210" y1="166" x2="210" y2="218" stroke="#B8721A" strokeWidth="2" />

      <g className="trace-node d5">
        <rect x="130" y="220" width="160" height="56" fill="#F7EEDC" stroke="#B8721A" strokeWidth="2" />
        <text x="210" y="243" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="13" fill="#B8721A">Sorting basics</text>
        <text x="210" y="261" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="10" fill="#B8721A">mastery 0.31 &mdash; root cause</text>
      </g>

      <g className="trace-node d6">
        <text x="210" y="305" textAnchor="middle" fontFamily="var(--font-plex-mono)" fontSize="11" fill="#4A554E">Start two levels down.</text>
      </g>
    </svg>
  )
}