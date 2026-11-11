import { SPEECH_MODELS, findModel } from "@omnicast/shared";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import type { Env } from "../types.js";

/**
 * The macOS app reads its download catalog from here so new models can ship
 * without an app update.
 */
export const modelsRoute = new Hono<Env>()
  .get("/", (c) => c.json({ items: SPEECH_MODELS }))
  .get("/:id", (c) => {
    const model = findModel(c.req.param("id"));
    if (!model) throw new HTTPException(404, { message: "Unknown model" });
    return c.json(model);
  });
