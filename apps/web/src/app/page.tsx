import { SPEECH_MODELS } from "@omnicast/shared";
import Link from "next/link";
import { GlassCard, Kbd, Pill } from "@/components/glass";
import { SearchPreview } from "@/components/search-preview";

const FEATURES = [
  {
    title: "Application search",
    body: "Every installed app, matched fuzzily and ranked by what you actually open. Nothing else in the list — sub-10 ms on a warm index.",
    icon: "⌘",
  },
  {
    title: "Clipboard history",
    body: "Every copy, in its own panel, searchable and scoped by source app. Secrets from password managers are skipped automatically.",
    icon: "📋",
  },
  {
    title: "On-device dictation",
    body: "Hold 🌐 fn, speak, release. A drop rises from the bottom of the screen and opens into a live meter. Audio never leaves the machine.",
    icon: "🎙️",
  },
  {
    title: "Your models, your choice",
    body: "Pick a speech model after install — from a 32 MB draft model to large-v3 turbo — and swap any time.",
    icon: "🧠",
  },
];

export default function Home() {
  return (
    <main className="mx-auto w-full max-w-6xl px-6 pb-24 pt-16">
      <nav className="mb-20 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="glass flex size-9 items-center justify-center rounded-xl text-sm">◎</div>
          <span className="text-sm font-medium tracking-tight">Omnicast</span>
        </div>
        <div className="flex items-center gap-2 text-sm">
          <Link href="/dashboard" className="glass-soft rounded-full px-4 py-2 hover:bg-white/10">
            Dashboard
          </Link>
          <a
            href="https://github.com/haxzie/omnicast"
            className="glass rounded-full px-4 py-2 hover:bg-white/15"
          >
            Download
          </a>
        </div>
      </nav>

      <section className="grid items-center gap-12 lg:grid-cols-2">
        <div>
          <Pill>
            <span className="size-1.5 rounded-full bg-emerald-400" /> Native macOS · Apple silicon
          </Pill>
          <h1 className="mt-6 text-balance text-5xl font-semibold leading-[1.05] tracking-tight sm:text-6xl">
            Spotlight, but it
            <span className="bg-gradient-to-r from-accent to-accent-warm bg-clip-text text-transparent">
              {" "}
              keeps up with you
            </span>
            .
          </h1>
          <p className="mt-6 max-w-lg text-pretty text-lg text-haze">
            Omnicast replaces Spotlight with a launcher that does one thing properly — open your
            apps — and adds press-to-talk dictation powered by speech models that run entirely on
            your Mac.
          </p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <a
              href="#download"
              className="glass rounded-full px-5 py-3 text-sm font-medium hover:bg-white/15"
            >
              Download for macOS
            </a>
            <span className="text-sm text-haze">
              Launcher <Kbd>⌥</Kbd> <Kbd>Space</Kbd> · Dictate hold <Kbd>🌐 fn</Kbd>
            </span>
          </div>
        </div>
        <SearchPreview />
      </section>

      <section className="mt-28 grid gap-4 sm:grid-cols-2">
        {FEATURES.map((f) => (
          <GlassCard key={f.title} className="p-7">
            <div className="glass-soft mb-5 flex size-10 items-center justify-center rounded-xl">
              {f.icon}
            </div>
            <h3 className="text-lg font-medium tracking-tight">{f.title}</h3>
            <p className="mt-2 text-sm leading-relaxed text-haze">{f.body}</p>
          </GlassCard>
        ))}
      </section>

      <section id="download" className="mt-28">
        <h2 className="text-3xl font-semibold tracking-tight">Choose a speech model</h2>
        <p className="mt-3 max-w-xl text-haze">
          Models download on demand from inside the app. Everything runs locally — no account, no
          upload, works on a plane.
        </p>
        <div className="mt-8 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {SPEECH_MODELS.map((m) => (
            <GlassCard key={m.id} className="p-6">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <h3 className="font-medium">{m.name}</h3>
                  <p className="mt-1 font-mono text-[11px] uppercase tracking-wide text-haze">
                    {m.languages === "en" ? "English" : "99 languages"} · ~{m.realtimeFactor}× realtime
                  </p>
                </div>
                {m.recommended && (
                  <span className="glass-soft rounded-full px-2 py-1 text-[10px] text-emerald-300">
                    Recommended
                  </span>
                )}
              </div>
              <p className="mt-4 text-sm text-haze">{m.description}</p>
              <p className="mt-5 font-mono text-xs text-white/60">
                {(m.bytes / 1e6).toFixed(0)} MB
              </p>
            </GlassCard>
          ))}
        </div>
      </section>

      <footer className="mt-28 flex flex-col items-center gap-2 text-sm text-haze">
        <p>Omnicast · built for macOS 14 and later</p>
        <p className="font-mono text-xs">⌥Space to begin</p>
      </footer>
    </main>
  );
}
