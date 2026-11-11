import { z } from "zod";

export const dictationSchema = z.object({
  id: z.string().min(1),
  text: z.string(),
  /** Audio length in seconds. */
  durationMs: z.number().int().nonnegative(),
  /** Wall-clock time the transcription took. */
  transcribeMs: z.number().int().nonnegative(),
  modelId: z.string().min(1),
  appBundleId: z.string().nullish(),
  appName: z.string().nullish(),
  language: z.string().nullish(),
  wordCount: z.number().int().nonnegative(),
  createdAt: z.number().int(),
});
export type Dictation = z.infer<typeof dictationSchema>;

export const createDictationSchema = dictationSchema.omit({ id: true, wordCount: true }).extend({
  id: z.string().min(1).optional(),
  createdAt: z.number().int().optional(),
});
export type CreateDictation = z.infer<typeof createDictationSchema>;

export const deviceSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  platform: z.literal("macos"),
  appVersion: z.string(),
  lastSeenAt: z.number().int(),
});
export type Device = z.infer<typeof deviceSchema>;

export const registerDeviceSchema = deviceSchema.omit({ lastSeenAt: true });
export type RegisterDevice = z.infer<typeof registerDeviceSchema>;

export const listQuerySchema = z.object({
  q: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
  cursor: z.coerce.number().int().optional(),
});

export const statsSchema = z.object({
  dictations: z.number().int(),
  words: z.number().int(),
  secondsDictated: z.number(),
  /** Words per minute saved vs. a 40 wpm typist. */
  minutesSaved: z.number(),
});
export type Stats = z.infer<typeof statsSchema>;
