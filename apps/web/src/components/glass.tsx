import type { ReactNode } from "react";

export function GlassCard({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={`glass rounded-3xl ${className}`}>{children}</div>;
}

export function Pill({ children }: { children: ReactNode }) {
  return (
    <span className="glass-soft inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs text-haze">
      {children}
    </span>
  );
}

export function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="glass-soft rounded-md px-1.5 py-0.5 font-mono text-[11px] text-white/80">
      {children}
    </kbd>
  );
}
