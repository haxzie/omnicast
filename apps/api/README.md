# Omnicast API

Hono on Cloudflare Workers, Drizzle ORM over D1.

| Route | |
|---|---|
| `GET /health` | liveness |
| `GET /v1/dictations` | list, `?q=` full-text-ish search, keyset pagination via `?cursor=` |
| `POST /v1/dictations` | upsert by id — the app retries offline-first, so the same id can arrive twice |
| `DELETE /v1/dictations/:id` | |
| `GET /v1/dictations/stats` | counts, words, seconds, estimated minutes saved |
| `PUT /v1/devices` | register / heartbeat a Mac |
| `GET /v1/models` | the downloadable speech-model catalog the app reads |

Auth is a bearer token in `OMNICAST_API_TOKEN`. When it is unset the API stays open, so
`wrangler dev` works with no setup; set it before deploying anywhere public.

```bash
pnpm db:generate        # regenerate migrations after editing src/db/schema.ts
pnpm db:migrate:local   # apply to the local D1
pnpm dev
```
