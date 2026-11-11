import Link from "next/link";
import { GlassCard } from "@/components/glass";
import { api } from "@/lib/api";

export const dynamic = "force-dynamic";

function timeAgo(ms: number): string {
  const s = Math.max(0, Math.round((Date.now() - ms) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}

export default async function Dashboard({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const [list, stats] = await Promise.all([api.dictations(q), api.stats()]);
  const items = list?.items ?? [];
  const offline = list === null;

  return (
    <main className="mx-auto w-full max-w-5xl px-6 pb-24 pt-16">
      <nav className="mb-12 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-3">
          <div className="glass flex size-9 items-center justify-center rounded-xl text-sm">◎</div>
          <span className="text-sm font-medium tracking-tight">Omnicast</span>
        </Link>
        <span className="font-mono text-xs text-haze">{api.baseUrl}</span>
      </nav>

      <h1 className="text-4xl font-semibold tracking-tight">Dictation history</h1>
      <p className="mt-3 text-haze">
        Everything you dictated on your Macs, synced from the app.
      </p>

      <div className="mt-8 grid gap-3 sm:grid-cols-4">
        {[
          { label: "Dictations", value: stats?.dictations ?? 0 },
          { label: "Words", value: (stats?.words ?? 0).toLocaleString() },
          { label: "Seconds spoken", value: stats?.secondsDictated ?? 0 },
          { label: "Minutes saved", value: stats?.minutesSaved ?? 0 },
        ].map((s) => (
          <GlassCard key={s.label} className="p-5">
            <p className="text-xs uppercase tracking-wide text-haze">{s.label}</p>
            <p className="mt-2 text-2xl font-semibold tabular-nums">{s.value}</p>
          </GlassCard>
        ))}
      </div>

      <form className="mt-10" action="/dashboard">
        <input
          name="q"
          defaultValue={q ?? ""}
          placeholder="Search transcripts…"
          className="glass w-full rounded-2xl px-5 py-3 outline-none placeholder:text-white/35"
        />
      </form>

      <div className="mt-6 space-y-3">
        {offline && (
          <GlassCard className="p-6 text-sm text-haze">
            Can&apos;t reach the API at <span className="font-mono">{api.baseUrl}</span>. Start it
            with <span className="font-mono">pnpm --filter @omnicast/api dev</span>.
          </GlassCard>
        )}
        {!offline && items.length === 0 && (
          <GlassCard className="p-6 text-sm text-haze">
            Nothing yet. Hold <span className="font-mono">fn</span> in the macOS app and say
            something.
          </GlassCard>
        )}
        {items.map((d) => (
          <GlassCard key={d.id} className="p-6">
            <p className="leading-relaxed">{d.text}</p>
            <div className="mt-4 flex flex-wrap items-center gap-3 font-mono text-[11px] text-haze">
              <span>{timeAgo(d.createdAt)}</span>
              <span>·</span>
              <span>{d.modelId}</span>
              <span>·</span>
              <span>{(d.durationMs / 1000).toFixed(1)}s audio</span>
              <span>·</span>
              <span>{d.wordCount} words</span>
              {d.appName && (
                <>
                  <span>·</span>
                  <span>into {d.appName}</span>
                </>
              )}
            </div>
          </GlassCard>
        ))}
      </div>
    </main>
  );
}
