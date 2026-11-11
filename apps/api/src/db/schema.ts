import { sql } from "drizzle-orm";
import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const devices = sqliteTable("devices", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  platform: text("platform").notNull().default("macos"),
  appVersion: text("app_version").notNull(),
  lastSeenAt: integer("last_seen_at").notNull(),
  createdAt: integer("created_at")
    .notNull()
    .default(sql`(unixepoch() * 1000)`),
});

export const dictations = sqliteTable(
  "dictations",
  {
    id: text("id").primaryKey(),
    // Deliberately not a foreign key: the app uploads offline-first and a
    // dictation may arrive before (or without) its device registration.
    deviceId: text("device_id"),
    text: text("text").notNull(),
    durationMs: integer("duration_ms").notNull(),
    transcribeMs: integer("transcribe_ms").notNull().default(0),
    modelId: text("model_id").notNull(),
    appBundleId: text("app_bundle_id"),
    appName: text("app_name"),
    language: text("language"),
    wordCount: integer("word_count").notNull().default(0),
    createdAt: integer("created_at").notNull(),
  },
  (t) => [
    index("dictations_created_at_idx").on(t.createdAt),
    index("dictations_device_idx").on(t.deviceId, t.createdAt),
  ],
);

export type DeviceRow = typeof devices.$inferSelect;
export type DictationRow = typeof dictations.$inferSelect;
