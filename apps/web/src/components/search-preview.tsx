"use client";

import { useEffect, useMemo, useState } from "react";

type Row = { icon: string; title: string; subtitle: string; kind: string };

const CORPUS: Row[] = [
  { icon: "🧭", title: "Safari", subtitle: "/Applications", kind: "app" },
  { icon: "🗒️", title: "Notes", subtitle: "/System/Applications", kind: "app" },
  { icon: "✉️", title: "Mail", subtitle: "/System/Applications", kind: "app" },
  { icon: "🎛️", title: "Logic Pro", subtitle: "/Applications", kind: "app" },
  { icon: "💬", title: "Slack", subtitle: "/Applications", kind: "app" },
  { icon: "🖥️", title: "Terminal", subtitle: "/System/Applications/Utilities", kind: "app" },
  { icon: "🧮", title: "Calculator", subtitle: "/System/Applications", kind: "app" },
  { icon: "📐", title: "Xcode", subtitle: "/Applications", kind: "app" },
];

/** Mirrors the subsequence scorer the macOS app uses, in miniature. */
function score(query: string, text: string): number {
  if (!query) return 1;
  const q = query.toLowerCase();
  const t = text.toLowerCase();
  let qi = 0;
  let points = 0;
  let streak = 0;
  for (let ti = 0; ti < t.length && qi < q.length; ti++) {
    if (t[ti] === q[qi]) {
      streak += 1;
      points += 1 + streak * 2 + (ti === 0 || t[ti - 1] === " " ? 8 : 0);
      qi += 1;
    } else {
      streak = 0;
    }
  }
  return qi === q.length ? points : 0;
}

export function SearchPreview() {
  const [query, setQuery] = useState("");
  const [typed, setTyped] = useState(0);
  const demo = "mail";

  useEffect(() => {
    if (query) return;
    const id = setInterval(() => setTyped((n) => (n + 1) % (demo.length + 14)), 260);
    return () => clearInterval(id);
  }, [query]);

  const effective = query || demo.slice(0, Math.min(typed, demo.length));

  const results = useMemo(
    () =>
      CORPUS.map((r) => ({ r, s: score(effective, `${r.title} ${r.subtitle}`) }))
        .filter((x) => x.s > 0)
        .sort((a, b) => b.s - a.s)
        .slice(0, 5)
        .map((x) => x.r),
    [effective],
  );

  return (
    <div className="glass w-full overflow-hidden rounded-[28px] p-2">
      <div className="flex items-center gap-3 px-4 py-3">
        <span className="text-xl opacity-60">⌘</span>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={effective || "Search applications…"}
          className="w-full bg-transparent text-xl outline-none placeholder:text-white/35"
          aria-label="Omnicast search preview"
        />
        <kbd className="glass-soft rounded-md px-2 py-1 font-mono text-[11px] text-white/60">⌥Space</kbd>
      </div>
      <div className="h-px bg-white/10" />
      <ul className="p-2">
        {results.length === 0 && (
          <li className="px-4 py-6 text-center text-sm text-haze">No results</li>
        )}
        {results.map((r, i) => (
          <li
            key={r.title}
            className={`flex items-center gap-3 rounded-2xl px-4 py-3 transition ${
              i === 0 ? "bg-white/10" : "hover:bg-white/5"
            }`}
          >
            <span className="text-lg">{r.icon}</span>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm">{r.title}</p>
              <p className="truncate text-xs text-haze">{r.subtitle}</p>
            </div>
            <span className="glass-soft rounded-full px-2 py-0.5 text-[10px] uppercase tracking-wide text-haze">
              {r.kind}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
