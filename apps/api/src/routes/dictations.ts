import { zValidator } from "@hono/zod-validator";
import { createDictationSchema, listQuerySchema } from "@omnicast/shared";
import { and, desc, eq, like, lt, sql } from "drizzle-orm";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { dictations } from "../db/schema.js";
import type { Env } from "../types.js";

export const dictationsRoute = new Hono<Env>()
  .get("/", zValidator("query", listQuerySchema), async (c) => {
    const { q, limit, cursor } = c.req.valid("query");
    const where = [
      q ? like(dictations.text, `%${q}%`) : undefined,
      cursor ? lt(dictations.createdAt, cursor) : undefined,
    ].filter(Boolean);

    const rows = await c
      .get("db")
      .select()
      .from(dictations)
      .where(where.length ? and(...where) : undefined)
      .orderBy(desc(dictations.createdAt))
      .limit(limit + 1);

    const hasMore = rows.length > limit;
    const items = hasMore ? rows.slice(0, limit) : rows;
    return c.json({
      items,
      nextCursor: hasMore ? (items.at(-1)?.createdAt ?? null) : null,
    });
  })
  .post("/", zValidator("json", createDictationSchema), async (c) => {
    const body = c.req.valid("json");
    const row = {
      ...body,
      id: body.id ?? crypto.randomUUID(),
      deviceId: c.get("deviceId"),
      createdAt: body.createdAt ?? Date.now(),
      wordCount: countWords(body.text),
    };

    // The app retries uploads offline-first, so the same id may arrive twice.
    const [saved] = await c
      .get("db")
      .insert(dictations)
      .values(row)
      .onConflictDoUpdate({ target: dictations.id, set: { text: row.text, wordCount: row.wordCount } })
      .returning();

    return c.json(saved, 201);
  })
  .delete("/:id", async (c) => {
    const [deleted] = await c
      .get("db")
      .delete(dictations)
      .where(eq(dictations.id, c.req.param("id")))
      .returning({ id: dictations.id });
    if (!deleted) throw new HTTPException(404, { message: "Dictation not found" });
    return c.json({ ok: true });
  })
  .get("/stats", async (c) => {
    const [row] = await c
      .get("db")
      .select({
        dictations: sql<number>`count(*)`,
        words: sql<number>`coalesce(sum(${dictations.wordCount}), 0)`,
        ms: sql<number>`coalesce(sum(${dictations.durationMs}), 0)`,
      })
      .from(dictations);

    const words = row?.words ?? 0;
    return c.json({
      dictations: row?.dictations ?? 0,
      words,
      secondsDictated: Math.round((row?.ms ?? 0) / 1000),
      // Dictating at ~150 wpm against a 40 wpm typist.
      minutesSaved: Math.round((words / 40 - words / 150) * 10) / 10,
    });
  });

function countWords(text: string): number {
  const trimmed = text.trim();
  return trimmed ? trimmed.split(/\s+/).length : 0;
}
