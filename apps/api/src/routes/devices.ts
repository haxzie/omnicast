import { zValidator } from "@hono/zod-validator";
import { registerDeviceSchema } from "@omnicast/shared";
import { desc } from "drizzle-orm";
import { Hono } from "hono";
import { devices } from "../db/schema.js";
import type { Env } from "../types.js";

export const devicesRoute = new Hono<Env>()
  .get("/", async (c) => {
    const rows = await c.get("db").select().from(devices).orderBy(desc(devices.lastSeenAt));
    return c.json({ items: rows });
  })
  .put("/", zValidator("json", registerDeviceSchema), async (c) => {
    const body = c.req.valid("json");
    const row = { ...body, lastSeenAt: Date.now() };
    const [saved] = await c
      .get("db")
      .insert(devices)
      .values(row)
      .onConflictDoUpdate({
        target: devices.id,
        set: { name: row.name, appVersion: row.appVersion, lastSeenAt: row.lastSeenAt },
      })
      .returning();
    return c.json(saved);
  });
