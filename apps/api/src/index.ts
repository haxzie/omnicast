import { Hono } from "hono";
import { cors } from "hono/cors";
import { HTTPException } from "hono/http-exception";
import { logger } from "hono/logger";
import { requireAuth, withDb } from "./middleware.js";
import { devicesRoute } from "./routes/devices.js";
import { dictationsRoute } from "./routes/dictations.js";
import { modelsRoute } from "./routes/models.js";
import type { Env } from "./types.js";

const app = new Hono<Env>();

app.use("*", logger());
app.use("*", (c, next) =>
  cors({
    origin: (c.env.ALLOWED_ORIGINS ?? "*").split(",").map((o) => o.trim()),
    allowHeaders: ["Content-Type", "Authorization", "X-Omnicast-Device"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  })(c, next),
);
app.use("*", withDb);

app.get("/", (c) => c.json({ name: "omnicast-api", version: "0.1.0" }));
app.get("/health", (c) => c.json({ ok: true, time: Date.now() }));

const v1 = new Hono<Env>()
  .use("*", requireAuth)
  .route("/dictations", dictationsRoute)
  .route("/devices", devicesRoute)
  .route("/models", modelsRoute);

app.route("/v1", v1);

app.onError((err, c) => {
  if (err instanceof HTTPException) return err.getResponse();
  console.error(err);
  return c.json({ error: "Internal Server Error" }, 500);
});

app.notFound((c) => c.json({ error: "Not Found" }, 404));

export default app;
export type AppType = typeof v1;
