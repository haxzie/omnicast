import type { MiddlewareHandler } from "hono";
import { HTTPException } from "hono/http-exception";
import { db } from "./db/index.js";
import type { Env } from "./types.js";

export const withDb: MiddlewareHandler<Env> = async (c, next) => {
  c.set("db", db(c.env.DB));
  c.set("deviceId", c.req.header("x-omnicast-device") ?? null);
  await next();
};

/**
 * Bearer-token auth. When no token is configured (local `wrangler dev` without
 * .dev.vars) the API stays open so the app can be run without setup.
 */
export const requireAuth: MiddlewareHandler<Env> = async (c, next) => {
  const expected = c.env.OMNICAST_API_TOKEN;
  if (!expected) return next();

  const header = c.req.header("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!timingSafeEqual(token, expected)) {
    throw new HTTPException(401, { message: "Invalid or missing API token" });
  }
  return next();
};

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
