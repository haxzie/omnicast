import type { Db } from "./db/index.js";

export interface Bindings {
  DB: D1Database;
  OMNICAST_API_TOKEN?: string;
  ALLOWED_ORIGINS?: string;
}

export interface Variables {
  db: Db;
  deviceId: string | null;
}

export type Env = { Bindings: Bindings; Variables: Variables };
