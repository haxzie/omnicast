import type { Dictation, Stats } from "@omnicast/shared";

const BASE = process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:8787";

async function get<T>(path: string): Promise<T | null> {
  try {
    const res = await fetch(`${BASE}${path}`, {
      headers: process.env.OMNICAST_API_TOKEN
        ? { authorization: `Bearer ${process.env.OMNICAST_API_TOKEN}` }
        : {},
      // The dashboard mirrors a local-first app; always read fresh.
      cache: "no-store",
    });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    // The API is optional — the dashboard renders an empty state without it.
    return null;
  }
}

export const api = {
  baseUrl: BASE,
  dictations: (q?: string) =>
    get<{ items: Dictation[]; nextCursor: number | null }>(
      `/v1/dictations?limit=50${q ? `&q=${encodeURIComponent(q)}` : ""}`,
    ),
  stats: () => get<Stats>("/v1/dictations/stats"),
};
