---
trigger: always_on
---

# Upsilon Hub: Project Map & Infrastructure

## 1. Project Background
Upsilon Hub is the umbrella repository for a multi-stack, high-performance turn-based tactical-RPG
ecosystem. It bridges a fast Go **battle engine** with a Go **platform gateway** (the **hub**), a
standalone Vue SPA, and a Go automation CLI. Since the Phase 6 cutover, the hub owns auth/identity,
matchmaking, economy, admin, the realtime **SSE** stream and the database schema, and serves the
built Vue SPA — the former Laravel `battleui` (and its Reverb WebSockets) are decommissioned.

The platform is on the **v3.0** trajectory: a four-game world (battle, tycoon, spy, digital) built by
composition. Today the platform substrates and game modules live as packages **inside the hub**
(`internal/platform/…`, `internal/games/…`), each an extraction candidate with the seam already
drawn. For the service→project ownership map, bridge topology, and contract/vision attribution, see
[`architecture/service_map.md`](../../architecture/service_map.md); current-state
shape is [`architecture/architecture_anchor.md`](../../architecture/architecture_anchor.md).

## 2. Who's Who (Service Architecture)

| Component | Stack | Role | Default Port |
|---|---|---|---|
| **upsilonhub** | Go | Platform gateway — auth/identity, session tokens, matchmaking, economy/loadout, admin, realtime SSE, DB schema + migrations/seed; serves the REST `/api/v1` and the built SPA. OTel-instrumented. | Hub `8090`, front door (Caddy) `8085` |
| **upsilonbattleui** | Vue 3 / Vite / Tailwind / TresJS | Standalone SPA (management UI + battle client + admin pages); talks to `/api/v1` with bearer tokens, listens on the SSE stream. Built and served by the hub. | Vite dev `5173` |
| **upsilonapi** | Go | The "Bridge" — high-performance JSON API for the engine; handles match state and engine callbacks. Not yet OTel-instrumented. | `8081` |
| **upsilonbattle** | Go | Core Battle Engine (`BattleArena`) — initiative, movement validation, damage, combat state. | Embedded in `upsilonapi` |
| **upsiloncli** | Go | Interactive terminal, E2E testing, and bot orchestration (goja JS scenarios). | N/A |
| **upsilonauth** ⚠️ | Go | **Extraction in progress — dark until cutover.** SSO trust seam being scaffolded out of the hub's `identity` package (2026-07-22): accounts, opaque tokens, introspection, GDPR, roles. Public via Caddy at `/api/v1/auth/*` **only after the Phase 4 cutover**; today nothing routes to it and the hub's in-process identity remains authoritative. Own database `upsilonauth`. | `8091` |
| **upsiloneconomy** ⚠️ | Go | **Extraction in progress — dark, internal-only.** Wallet/ledger/market being scaffolded out of the hub's `economy` package (2026-07-22); stays behind the hub (no Caddy route, ever — hub keeps the public shop/inventory endpoints and calls it S2S). Own database `upsiloneconomy`. | `8092` |
| **upsilonplatform** ⚠️ | Go (library) | **Shared mechanical kit, extracted from the hub 2026-07-22.** `respond` (envelope), `clock`, `observability`, `database`, `jobs` (River wrapper), `httpx` (S2S client). Every new/extracted service composes on it — copy nothing. Not a running service; no port. | N/A |

### 2.1 Shared Libraries (Go modules)
Standard definitions shared across the Go services:
- **upsilontypes** — shared domain models and cross-process vocabularies.
- **upsilonserializer** — specialized serialization for engine/game state.
- **upsilonmapdata** — geometric board data structures and grid boundaries.
- **upsilonmapmaker** — procedural map/grid generation.
- **upsilontools** — shared utilities and math helpers.
- **upsilonplatform** — shared mechanical kit (envelope/clock/observability/database/jobs/httpx);
  see §2 above — extracted from the hub 2026-07-22, used by `upsilonauth` and `upsiloneconomy`.

### 2.2 Infrastructure
- **upsilonaws** — Bash-based AWS provisioning (VPC, EC2, RDS PostgreSQL 18, Route 53, nginx SSL proxy) deploying to `eu-west-3`.

### 2.3 Databases (one per service, 2026-07-22)
Extraction moves to **one database per service on the shared Postgres instance** (dev
`postgres:18` container / prod RDS), not a shared database with per-domain schemas: `upsilon`
(hub), `upsilonauth`, `upsiloneconomy` — each with its own `DATABASE_URL`, relocatable later to
a dedicated instance with no SQL changes. Provisioned by `deploy/initdb/create_databases.sql`
(idempotent `\gexec`, mounted at cluster init — an existing dev volume needs
`docker compose down -v` once to pick it up). No cross-database SQL, ever; cross-service
references are UUID-only through the owning service's API.

## 3. Folder Organization

### 3.1 Umbrella layout
Each `upsilon*` directory is a Git submodule (except `upsilonserializer`, an in-tree Go module):
- `/upsilonhub`: Go platform gateway (API, SSE, DB schema, migrations/seed; serves the SPA).
- `/upsilonbattleui`: standalone Vue 3 + Vite SPA (management UI + battle client + admin).
- `/upsilonapi`: Go engine bridge server.
- `/upsilonbattle`: core engine logic (`BattleArena`) + battle domain rules.
- `/upsiloncli`: command-line tools and E2E test scenarios (goja JS).
- `/upsilontypes`, `/upsilonserializer`, `/upsilonmapdata`, `/upsilonmapmaker`, `/upsilontools`: shared Go libraries (see §2.1).
- `/upsilonaws`: AWS provisioning scripts (see §2.2).
- `/scripts`: operational shell/Python scripts for dev, CI, deployment, and code health.
- `/docs`: shared ATD documentation (Atoms).
- `/issues`: tracked project risks and technical debt.
- `/reporting`: architecture anchors, the v3 platform docs, and migration reports.
- `go.work`: Go workspace wiring all the Go modules together.

### 3.2 Hub internal architecture (`upsilonhub/internal/…`)
The hub is where the v3 platform is assembled by composition. Its packages:
- `platform/` — cross-cutting **substrate** services, each an extraction candidate:
  `identity` (auth/trust seam → future `upsilonauth` SSO), `economy` (wallet/ledger/market),
  `character`, `clock` (injected clock — never `time.Now()`), `jobs` (durable jobs — no ad-hoc goroutines/tickers).
- `games/` — game **modules**; today `battle` (with `upsilonapi`+`upsilonbattle` behind it).
  Composition rule: **games never import games**; cross-game influence flows only through platform
  state, shared vocabularies (items/effects/events), or the event bus.
- `gateway/` — the HTTP surface: auth, matchmaking, shop, profile, leaderboard, skills/equipment,
  admin, SPA serving, SSE, middleware, response envelopes, and the battle proxy.
- `events/` — domain event bus + envelope (the pre-MQ seam; idempotent on `event_id`).
- `transport/` — outbound/inbound transport plumbing (traceparent propagation).
- `observability/` — OpenTelemetry wiring (otelgin / otelpgx / OTLP export).
- `database/`, `seed/`, `config/`, `testutil/` — schema/queries, seeding, config, test helpers.

## 4. Operational Workflows

### Starting the Stack
- **Build**: `scripts/build_services.sh`.
- **Start**: `scripts/start_services.sh` (behind the Caddy front door at `:8085`).
- **Validation**: health check via `scripts/check_services.sh`.
- **Repo health**: `scripts/repo_status.sh [--fetch]` — umbrella + submodule preflight (see §5).

### Match Life Cycle (post–Phase 6)
1. **Creation**: players (SPA) or bots (`upsiloncli`) request a match via the hub's matchmaking API, through the Caddy front door.
2. **Simulation**: the hub dispatches to the `upsilonapi` bridge, which drives `upsilonbattle`'s ephemeral `BattleArena`.
3. **Observation**: live state (`match.found`, `game.started`, `turn.started`, board updates) is pushed to clients over the hub's **SSE** stream (`/api/v1/events`); the engine posts turn/board updates back to the hub via webhook.
4. **Archival**: on a victory condition the engine posts final results to the hub, persisted in PostgreSQL for progression tracking.

### Debugging
- **Log Parsing**: `scripts/upsilon_log_parser.sh` filters and colorizes engine events.
- **State Audit**: inspect `debug_board.json` or match resurrection state (ISS-054).

## 5. Testing Toolkit

### Core Scripts
- `scripts/trigger_one_ci_test.sh <name>`: run a specific E2E scenario. Accepts the name with or without the `edge_`/`e2e_` prefix and `.js` suffix (e.g. `movement_entity_collision`).
- `scripts/trigger_all_ci_tests.sh` / `scripts/trigger_quick_ci_tests.sh`: run the full / quick E2E suites.
- `scripts/run_all_unit_tests.sh`: executes all Go unit tests (and the Vue/Vitest suite).
- `scripts/check_services.sh`: health check for running docker/local services.
- `scripts/code_health_check.py`: the Zero-Error code-health audit (LOC, nesting, ATD link density).
- `scripts/repo_status.sh [--fetch]`: one-shot health check of the umbrella **and every submodule** — branch, HEAD, push-sync (ahead/behind), submodule-pointer coherence, and working-tree cleanliness in one aligned table. Exits non-zero if anything is dirty / unpushed / drifted, so it works as a pre- and post-push preflight. Run it before bumping submodule pointers and after pushing to confirm a coherent snapshot.

### Manual Verification
- `upsiloncli --farm`: starts a local match with automated bot players; targets the Caddy front door via `UPSILON_BASE_URL` (set at compose level to `http://proxy:8085` for the dev container, `http://localhost:8085` from the host — the only entry point routing both `/api/v1/auth/*` and the hub API).
- `scripts/upsilon_log_parser.sh`: parses and colorizes engine logs for debugging.

## 6. Environments
- **Dev/DevContainer**: fully containerized (`docker-compose.yaml` + Caddy + Postgres 18). Standard for development.
- **CI**: `docker-compose.ci.yaml` orchestrates the ephemeral stack (`db` → `hub-migrate` → `hub-seed` → `hub` → `proxy` → `engine` → `tester`) via GitHub Actions.
- **Prod**: `docker-compose.prod.yaml` (`db` → `db-init` → `hub` → `proxy` → `engine` → `cli`); data in the `db_data` volume.
- **Cloud**: `upsilonaws` provisions AWS (`eu-west-3`).
