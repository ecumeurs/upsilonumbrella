---
name: dev-env
description: Bring up, tear down, and operate the Upsilon Hub local dev environment — docker compose lifecycle, per-service database migrate/seed/drop, service start/stop/health, and the testing toolkit (single/quick/full CI scenarios, Go unit tests, Playwright). Use this whenever asked to start/stop/reset the dev env, seed or drop a database, check service health, or run tests locally.
---

# Dev Env

Verified, working procedure for the local dev stack (cold-started and run end
to end on 2026-09-16). Follow it verbatim rather than rediscovering — it
covers two gotchas that aren't obvious from the scripts alone (see
**Gotchas** at the bottom).

## Architecture recap

- Everything Go/Node runs **inside the `app` container** (the devcontainer),
  not on the host. The container's own `CMD` is `sleep infinity` — nothing
  auto-builds, auto-migrates, or auto-starts on `docker compose up`.
- `db` (Postgres 18) is shared: `deploy/initdb` provisions one database per
  service — `upsilon`, `upsilonauth`, `upsiloneconomy` — on the same
  instance. The hub uses `upsilon` directly (declared in its
  `DATABASE_URL` at compose level); economy/auth get retargeted to their own
  database by `scripts/start_services.sh`'s `sed` rewrite (see **Database**
  below; formerly Gotcha #5, now resolved — ISS-161).
- `proxy` (Caddy) is the stable front door on `:8085`, routing
  `/api/v1/auth/*` and `/api/v1/admin/users*` to auth, `/api/v1/events` (SSE)
  and everything else to the hub.
- Five app-level processes run *inside* `app`, managed by
  `scripts/{start,stop,check}_services.sh` via PID-file + port tracking (not
  docker containers themselves): Engine (upsilonapi), Economy, Auth, Hub,
  Vue frontend (Vite dev server).

## Ports — in (inside `app`) vs out (published to host)

`start_services.sh`/`check_services.sh` print the **in-container** port. Only
some of these are actually published to the host by
`docker-compose.yaml` + `docker-compose.override.yaml` (the override fully
replaces the `app` service's port list — check both files if a port seems to
have vanished).

| Process / container | In (inside `app` or its own container) | Out (host) | Reach it from the host via |
|---|---|---|---|
| Upsilon Engine (`upsilonapi`) | 8081 | **8081** | `http://localhost:8081` |
| Upsilon Economy | 8092 | *(not published)* | internal-only by design (S2S from hub, never a Caddy route) — `docker compose exec app curl localhost:8092/...` |
| Upsilon Auth | 8091 | *(not published)* | via front door only: `http://localhost:8085/api/v1/auth/*` |
| Upsilon Hub | 8090 | **8090** | `http://localhost:8090` direct, or via front door |
| Vue frontend (Vite dev) | 5173 | **5173** | `http://localhost:5173` |
| Caddy proxy (front door) | 8085 (own container) | **8085** | `http://localhost:8085` — canonical entry point; Playwright's default `baseURL` |
| otel-collector | 4317 (gRPC), 4318 (HTTP) | **4317, 4318** | OTLP endpoints |
| Postgres (`db`) | 5432 (own container) | **5433** | `psql -h localhost -p 5433 -U postgres` |
| `app` container misc | — | **8000** (override only) | published but currently unused — vestigial from the decommissioned Laravel Reverb setup |

Health-check probes exist per Go binary too: `./bin/<svc> -healthcheck` hits
its own local `/up` route and exits 0/1 (used by the CI compose healthchecks;
handy for a deeper-than-port check inside `app`).

## Docker: build / start / stop / purge

Compose files: `docker-compose.yaml` (base, tracked) +
`docker-compose.override.yaml` (untracked, local port overrides — auto-applied,
no `-f` flag needed). Requires the external network `ollama_network` to
already exist (`docker network ls | grep ollama_network`; create with
`docker network create ollama_network` if missing).

```bash
# Check what's running
docker compose ps

# Build + start everything (safe to re-run; rebuilds only on Dockerfile/context changes)
docker compose up -d --build

# Stop containers, KEEP volumes (db data survives) — safe, default choice
docker compose down

# Stop AND wipe the db volume — DESTRUCTIVE, confirm with the user first.
# Needed once per fresh/broken volume to let deploy/initdb auto-provision the
# three per-service databases on cluster init.
docker compose down -v

# Free disk space without touching this stack's live data:
docker builder prune -f        # clear build cache (safe, just slows next build)
docker image prune -f          # remove dangling (untagged) images (safe)
docker system df               # see what's actually using space first

# Host-wide nuke of ALL unused containers/images/volumes/networks across
# every project on the machine — NEVER run without explicit user confirmation.
docker system prune -af --volumes
```

## Database: seed / migrate / drop

Each Go service binary is its own migration/seed tool (flags: `-migrate`,
`-seed`; hub additionally has `-migrate-mode {full,baseline,river-only}` and
`-seed-leaderboard`). All DB flags below run **inside the `app` container**.
The container's inherited `DATABASE_URL` (from `docker-compose.yaml`) now
carries `?sslmode=disable` by default (ISS-161; formerly Gotcha #1, now
retired) — a bare command using it as-is, or a value derived from it via
`sed` (as `start_services.sh` does for economy/auth), automatically keeps
that query string. Commands below that hand-type a different database's
full URL still spell out `?sslmode=disable` explicitly, since Postgres
itself doesn't have SSL enabled and a literal, non-derived URL doesn't
inherit anything.

```bash
# From the repo root on the host, everything below is wrapped as:
docker compose exec -T app bash -lc '<command>'

# --- Hub (uses the container's default DATABASE_URL db — "upsilon") ---
cd /workspace/upsilonhub
./bin/upsilonhub -migrate-mode full   # idempotent — safe to re-run
./bin/upsilonhub -seed                # idempotent — skill-template catalog only
# accounts/shop catalog are NOT seeded here (moved to auth/economy, Phase 3-4)

# --- Economy (db "upsiloneconomy") ---
cd /workspace/upsiloneconomy
env DATABASE_URL="postgres://postgres:postgres@db:5432/upsiloneconomy?sslmode=disable" ./bin/upsiloneconomy -migrate
env DATABASE_URL="postgres://postgres:postgres@db:5432/upsiloneconomy?sslmode=disable" ./bin/upsiloneconomy -seed       # shop catalog

# --- Auth (db "upsilonauth") ---
cd /workspace/upsilonauth
env DATABASE_URL="postgres://postgres:postgres@db:5432/upsilonauth?sslmode=disable" ./bin/upsilonauth -migrate
# ADMIN_INITIAL_PASSWORD gates the admin/dummy/admin2 seed block (warn+skip if unset)
env ADMIN_INITIAL_PASSWORD="AdminPassword123!" DATABASE_URL="postgres://postgres:postgres@db:5432/upsilonauth?sslmode=disable" ./bin/upsilonauth -seed
```

`scripts/start_services.sh` already runs the economy/auth migrate+seed pair
itself on every start (idempotent, so this is normally automatic — see
**Services** below). The hub's own migrate+seed is *not* wired into
`start_services.sh`; run it manually as above when needed (fresh volume,
schema drift, or just to be sure).

### Dropping a database (destructive — confirm with the user first)

Three blast radii, smallest to largest:

```bash
# 1. Drop + recreate ONE service's schema only (keeps the database itself,
#    e.g. "upsilon", "upsilonauth", "upsiloneconomy"), then re-migrate+seed it
#    with the commands above. This is exactly what scripts/seed_ci.sh does
#    for the hub — it is a reset+reseed combo, not a standalone drop.
docker compose exec -T db psql -U postgres -d upsilonauth -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'

# 2. Drop one whole per-service DATABASE, then re-provision it via the
#    idempotent initdb script (safe to pipe through psql manually — see its
#    own header comment) before migrate+seed:
docker compose exec -T db psql -U postgres -d postgres -c 'DROP DATABASE upsiloneconomy;'
docker compose exec -T db psql -U postgres -d postgres < deploy/initdb/create_databases.sql

# 3. Nuclear: wipe the entire shared Postgres volume (every service's DB,
#    plus any unrelated schemas that happen to live on the same dev volume).
docker compose down -v
docker compose up -d --build
# create_databases.sql auto-runs via docker-entrypoint-initdb.d on this fresh
# volume — no manual re-provisioning step needed after this path.
```

`scripts/seed_ci.sh` is a combined **reset+reseed** for the hub's own DB only
(`DROP SCHEMA public CASCADE` then `-migrate-mode full` then `-seed`) — it is
called automatically by `trigger_quick_ci_tests.sh` / `trigger_all_ci_tests.sh`
as their test-fixture reset. Don't run it standalone against a dev DB you
care about without confirming first; prefer the idempotent migrate+seed
commands above for routine "just make sure it's seeded" checks. (Flagged
stale/single-DB-assumption in ISS-123 — it only resets the hub's db, not
auth/economy.)

## Services: start / stop / check health

All three run **inside the `app` container**, from `/workspace`:

```bash
docker compose exec -T app bash -lc 'cd /workspace && ./scripts/start_services.sh'
docker compose exec -T app bash -lc 'cd /workspace && ./scripts/check_services.sh'
docker compose exec -T app bash -lc 'cd /workspace && ./scripts/stop_services.sh'
```

- `start_services.sh` is authoritative: it stops any tracked stack first,
  then starts Engine → (migrate+seed economy) → Economy → (migrate+seed
  auth) → Auth → Hub → Vue frontend, verifying each is actually listening on
  its port before moving on. Works from the inherited container env alone —
  no `DATABASE_URL` override needed on the command line (ISS-161; formerly
  required per Gotcha #1, now retired).
- `check_services.sh` runs three layers and exits non-zero if any fails:
  (1) `.services.pids` liveness — PID alive + port bound, `[RUNNING]` /
  `[PENDING]` / `[DOWN]`; (2) HTTP health — hits each service's own `/health`
  or `/up` route directly, plus the Caddy front door, catching a
  bound-but-wedged process or a Caddyfile/env routing break that port checks
  miss; (3) database schema depth — for each service's expected database
  (`upsilon`/`upsilonauth`/`upsiloneconomy`), asserts `DATABASE_URL`'s path
  segment actually matches that name (failing loudly on drift instead of
  silently checking the wrong database — this is what caught ISS-161) before
  confirming `schema_migrations` exists, isn't left `dirty` by an
  interrupted migrate, and its version matches the highest migration file in
  that service's `db/migrations/` — catches exactly the "process is up, DB
  was never migrated" gap in Gotcha #3 that a port/HTTP check alone can't
  see.
- `stop_services.sh` does a graceful PID-file kill, then a forceful
  `ss`-based port sweep (8090, 5173, 8081, 8092, 8091) as a backstop.
- `scripts/zombie_killer.sh` is a harder hammer for hung `upsiloncli` /
  `upsilonapi` / `upsilonbattle` processes that survive the above (`pkill -9
  -f`) — reach for it only if `stop_services.sh` reports stuck ports.

## Testing toolkit

All test scripts run **inside the `app` container** from `/workspace` and
pre-flight-check `check_services.sh` themselves (they refuse to run if the
stack isn't up).

```bash
# One scenario (E2E or edge case) — does NOT touch the database itself.
# Accepts the name with/without "edge_"/"e2e_" prefix and ".js" suffix.
./scripts/trigger_one_ci_test.sh movement_entity_collision

# Quick suite: seed_ci.sh reset+reseed, then 4 critical E2E scenarios +
# 2 critical Playwright specs (battle_arena_sandbox, battle_arena).
./scripts/trigger_quick_ci_tests.sh

# Go unit tests (all modules via go.work; auth/economy run at -p 1 to avoid
# testcontainers-Postgres contention — see ISS-132). Note: despite
# UPSILON.md's description, this script currently runs Go tests only, no
# Vue/Vitest suite exists in upsilonbattleui's package.json.
./scripts/run_all_unit_tests.sh
```

**`./scripts/trigger_all_ci_tests.sh` (full E2E + edge suite, also does a
seed_ci.sh reset first) — do not run this unless the user directly asks for
it.** It's the heaviest option and resets the hub DB as a side effect;
default to `trigger_one_ci_test.sh` or `trigger_quick_ci_tests.sh` for
routine verification.

### Playwright directly (finer control than the quick suite)

```bash
cd upsilonbattleui
npm install                                    # only if node_modules is missing
npx playwright test tests/playwright/battle_arena.spec.ts   # one spec
npx playwright test                                          # all specs
```

- Default `baseURL` is `http://localhost:8085` (the Caddy front door) —
  override with `PLAYWRIGHT_BASE_URL` if pointing elsewhere.
- No `webServer` block in `playwright.config.ts` — the stack (hub serving
  `HUB_SPA_DIR`, behind the proxy) must already be running via
  `start_services.sh`; Playwright does not launch it for you.
- HTML report lands in `upsilonbattleui/playwright-report/`; a quick-suite
  failure additionally writes `upsilonbattleui/playwright_last_run.log`.

## Gotchas

1. **RETIRED — `DATABASE_URL` needed `?sslmode=disable`.** Historical: the
   `app` container's inherited `DATABASE_URL` (from `docker-compose.yaml`)
   used to be `postgres://postgres:postgres@db:5432/postgres` — no
   `sslmode` — so every Go binary's `-migrate`/`-seed`/serve call failed with
   `pq: SSL is not enabled on the server` unless `?sslmode=disable` was
   appended by hand, and `start_services.sh` didn't add it itself. Fixed at
   compose level in ISS-161: the inherited `DATABASE_URL` now carries
   `?sslmode=disable` by default, so `start_services.sh` (and any command
   that inherits or `sed`-derives from it) works with no override needed.
2. **Pre-existing (non-fresh) db volumes lack the per-service databases.**
   `deploy/initdb/create_databases.sql` only runs on first cluster init
   (fresh volume). On an older volume, `upsilon`/`upsilonauth`/`upsiloneconomy`
   silently don't exist until you pipe that file through `psql` manually (see
   **Docker: purge** / **Database: drop** above) — it says in its own header
   comment that this is safe and idempotent, no need for `docker compose down
   -v` just for this.
3. **Hub's own migrate/seed isn't in `start_services.sh`.** Only
   economy/auth get auto-provisioned on every start. If the hub's schema is
   missing/stale (fresh volume, or after a schema-only drop), run its
   `-migrate-mode full` + `-seed` manually first (see **Database** above) —
   otherwise the hub process will start against a DB with no tables.
4. **Admin seeding is silently skipped without `ADMIN_INITIAL_PASSWORD`.**
   `start_services.sh` doesn't set it, so `upsilonauth -seed` logs `WARN
   ADMIN_INITIAL_PASSWORD not set. Admin seeding skipped.` — fine for
   ordinary dev, but set it explicitly if you need to log in as
   admin/dummy/admin2 locally.
5. **RESOLVED — the hub never actually used the "upsilon" database
   (ISS-161).** Historical: `deploy/initdb` provisions
   `upsilon`/`upsilonauth`/`upsiloneconomy`, and economy/auth *did* get their
   `DATABASE_URL` rewritten to their own db by `start_services.sh`
   (`ECONOMY_DB_URL`/`AUTH_DB_URL`, via a `sed` swap of the path segment),
   but the hub line never got the same treatment — it just inherited the
   devcontainer's raw `DATABASE_URL`, whose path segment was `postgres`. The
   hub's schema and data lived in the shared `postgres` database while the
   dedicated `upsilon` database sat empty and unused. Fixed 2026-09-16 by
   pointing the hub's `DATABASE_URL` at `upsilon` directly in
   `docker-compose.yaml` (root cause was narrower than a missing
   `start_services.sh` rewrite — see the ISS-161 resolution note) and
   re-migrating/seeding the hub into it. `check_services.sh` now asserts
   each service's `DATABASE_URL` path segment against its expected database
   name and fails loudly on a mismatch, rather than just reading whatever it
   finds.
