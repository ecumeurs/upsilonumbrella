---
name: add-a-service
description: Wire up a new standalone Go service on the shared upsilonplatform kit (own repo/submodule, own database), or extract an existing domain out of the hub into one. Use whenever asked to add a new platform service, stand up a new microservice on upsilonplatform, or split a domain out of upsilonhub.
---

# Add a Service

Dependency-ordered playbook for adding a service to the Upsilon platform.
Follow the order below — each stage leaves the umbrella buildable/CI-green
before the next starts. A "service" here is a standalone Go process in its
own repo/submodule, with its own database, assembled from the shared kit
(`upsilonplatform`) rather than reimplementing its plumbing.

## 0. Decide the seams first (architecture gate)

Before any repo exists, answer in writing (an architecture note or extraction
doc, reviewed by a human):

- **What does it own?** Tables, invariants, vocabulary — one sentence per
  table.
- **Public or internal?** Public services get a Caddy route on the front
  door (`:8085`); internal services are only reachable service-to-service,
  and `/internal/*` is black-holed at the proxy. Prefer internal — the hub
  composes the public API.
- **What crosses the boundary?** Cross-service references are **UUIDs
  only** — no foreign keys, no SQL joins across services, ever. Ownership
  checks go through the owning service's API. If today's code joins across
  the future seam, design the read model or RPC first.
- **Sync or durable?** User-facing calls are synchronous RPC. Anything
  fired from a settlement/webhook/background path must be a durable River
  job on the caller side plus an idempotency key enforced by the callee.

## 1. ATD governance (before any code)

1. Create the repo's `docs/` with **exactly one** `contract_<name>.atom.md`
   (type CONTRACT) and **one** `vision_<name>.atom.md` (type VISION), layer
   BUSINESS, with `parents` pointing at the umbrella's shared contract and
   vision atoms. Settle both **before** any business atom or business code
   — no business-layer change ships without its settled atom.
2. Copy the `.atd` config from an existing service repo.
3. Register the project in the umbrella `.atd.workspace`
   (`{"name": "<name>", "path": "<name>"}`).

## 2. Repo + git integration

```bash
gh repo create ecumeurs/<name> --private --description "..."
# scaffold: README.md, go.mod (module github.com/ecumeurs/<name>, go 1.25.0),
#           .gitignore (bin/, *.log, .env), .atd, docs/  → commit, push
cd <umbrella-root> && git submodule add ../<name>.git <name>
```

- Submodule URLs are **relative** (`../<name>.git`) — they resolve against
  the umbrella origin.
- Add `./<name>` to the umbrella `go.work` `use` block. No `replace`
  directives — the workspace wires local source; run `go work sync`
  afterwards and expect go.mod/go.sum churn in sibling modules (dependency
  graph unification — commit it, it keeps standalone builds reproducible).
- Commit order is always **submodule first, then umbrella pointer bump**.

## 3. Service shell (the shape every service shares)

```
cmd/<name>/main.go       serve (default) | -migrate | -seed | -healthcheck
internal/config/         crash-early Load(): <NAME>_ADDR (default :<port>),
                          DATABASE_URL (mandatory), S2S_TOKEN (mandatory if
                          it has an internal surface), APP_DEBUG,
                          OTEL_SERVICE_NAME (default "<name>")
internal/<domain>/       domain package — MUST NOT import net/http
                          (transport isolation)
internal/api/            HTTP handlers (Gin), envelope + middleware from
                          the kit
db/migrations/ + embed.go  golang-migrate SQL, embedded
sqlc.yaml                sqlc codegen against the migrations
Dockerfile                see §7
docs/ .atd                see §1
```

Use the **`upsilonplatform` kit — never copy its code**. Import by path,
e.g. `github.com/ecumeurs/upsilonplatform/clock`. Packages:

- **respond** — builds the Standard JSON Message Envelope
  (`request_id, message, success, data, meta`); the sole producer of the
  wire response format.
- **middleware** — Gin middleware consuming that envelope: request
  unwrapping, request-id resolution/enforcement, error-to-envelope
  conversion (Recovery/NoRoute/NoMethod).
- **clock** — the injected world clock (`clock.System` / `clock.Fake`);
  domain and gateway code never call `time.Now()` directly.
- **observability** — OTel bootstrap (OTLP trace exporter, W3C
  `traceparent` propagation) and structured, trace-correlated logging.
- **database** — the OTel-instrumented pgx connection pool plus
  migrate/baseline entrypoints; schema-agnostic, each service supplies its
  own migration `fs.FS`.
- **jobs** — a River (Postgres-backed) client wrapper bound to the injected
  clock; all background/async work goes through it instead of ad-hoc
  goroutines or tickers.
- **httpx** — the internal service-to-service HTTP client: envelope-aware,
  `otelhttp`-traced, timeout-bound, retries idempotent GETs, surfaces
  non-2xx/`success:false` as a typed `*httpx.Error`.

Router chain, in this exact order:
`otelgin.Middleware(serviceName)` → `SetDebug` → `middleware.Envelope()` →
`observability.RequestIDSpanAttribute()` → error/recovery middleware.
Health: `GET /up` (envelope-free). The `-healthcheck` flag self-probes
`/up` and exits 0/1 — required because the runtime image is distroless (no
shell for compose healthchecks).

Port registry (extend it when you claim one): 8081 upsilonapi · 8085 Caddy
front door · 8090 upsilonhub · 8091 upsilonauth · 8092 upsiloneconomy ·
5173 Vite dev · 5433→5432 Postgres · 4317/4318 OTel collector.

## 4. Database (one database per service)

- Every service owns **its own database** on the shared Postgres instance
  — `postgres://…/<name>` — so it can move to a dedicated instance later
  without SQL changes. Never point two services at one database; never
  query another service's database.
- Add the `CREATE DATABASE` block to `deploy/initdb/create_databases.sql`
  (idempotent `\gexec` pattern). It runs on first cluster init: CI is
  always fresh; an existing dev volume needs `docker compose down -v` once
  to pick it up.
- Migrations: golang-migrate, embedded, run by your own `-migrate` mode
  (plus `jobs.Migrate` for River if you use jobs). Seed via `-seed`.
- **Seed determinism:** cross-service fixtures agree on ids because every
  seeded row uses `upsilontypes/seedids` (UUIDv5 of a stable name) — one
  service seeds accounts, another seeds a catalog, a third seeds gameplay
  against the same ids, in any order.

## 5. Wire contracts

- DTOs are **plain structs** in `upsilontypes/<name>v1` (transport
  isolation: no HTTP types). They are the frozen contract; version by
  adding packages (`<name>v2`), not by breaking fields.
- All payloads travel inside the standard envelope
  `{request_id, message, success, data, meta}` — byte-parity is a hard
  contract, which is why the envelope lives in the kit.

## 6. Docker

- Dockerfile with **build context = umbrella repo root**: copy `go.work` +
  every module's `go.mod`, `go mod download`, copy source, build only your
  module; final stage `gcr.io/distroless/static-debian12:nonroot`, binary
  at `/app/<name>`, `EXPOSE <port>`. Add a `Dockerfile.dockerignore`.
- Compose (mirrored between CI and prod compose files): a
  `<name>-migrate → <name>-seed → <name>` chain hanging off
  `db: service_healthy`, with healthcheck
  `[ "CMD", "/app/<name>", "-healthcheck" ]`. Same image, different args.
- **Adding a module to `go.work` breaks OTHER images until you touch
  them.** Three context strategies coexist across the fleet:
  1. *Full-workspace copy*: some services `COPY go.work` + **every**
     module's `go.mod` — your new module's `go.mod` must be added to their
     COPY lists or their `go mod download` fails.
  2. *Minimal `go work init`*: other services are immune to go.work growth,
     but if a service starts importing your module, add it to that
     Dockerfile's COPY + `go work init` list. Mind transitive private
     deps: pulling in one shared library can drag several others
     (pseudo-versioned private repos) into the workspace too.
  3. *Per-Dockerfile ignore allowlists* (`<svc>/Dockerfile.dockerignore`
     with `*` + `!dirs`): any newly needed directory must ALSO be
     un-ignored there, or COPY fails with `"/<dir>": not found`.
  After any workspace change, rebuild **all** images
  (`docker compose -f docker-compose.ci.yaml build`) before trusting the
  stack.

## 7. Service-to-service calls & security

- Callers use `upsilonplatform/httpx`: per-service base URL from config,
  `WithInternalToken` (sent as `X-Internal-Token`), default 5s timeout,
  GET-only bounded retries, otelhttp transport (traceparent propagates
  automatically), `X-Request-ID` carried from context.
- Callees guard `/internal/v1/*` with a middleware comparing
  `X-Internal-Token` via `crypto/subtle.ConstantTimeCompare`; failure →
  401 envelope.
- The front door must never expose internal surfaces: Caddy
  `respond /internal/* 404`.
- Auth of end users is a single service's monopoly (identity/SSO): validate
  bearers via its introspection endpoint (with a short-TTL cache), never by
  reading its database directly.

## 8. Wire into the local dev orchestration scripts

This is the step that's easiest to skip: a service can compile, pass CI,
and get a Caddy route while still being invisible to local dev — because
`scripts/start_services.sh`, `scripts/stop_services.sh`, and
`scripts/check_services.sh` **hardcode every service**. Nothing wires a new
one in automatically. Edit all three:

- **`scripts/start_services.sh`** — if the service owns a database, add a
  migrate+seed provisioning block before starting it (mirror the pattern
  already used for other services in that file: retarget `DATABASE_URL` to
  the service's own database with a `sed` swap of the path segment, then
  run `-migrate` then `-seed`, failing loudly with a clear error if either
  step fails). Then add the start call itself:
  ```bash
  start_service "<Display Name>" "<repo-dir>" "<run command>" "<name>.log" <port>
  ```
  Order matters: place it before any service whose S2S client needs to
  find it live at boot (e.g. before the hub, if the hub calls it).
- **`scripts/stop_services.sh`** — add the service's port to the
  `PORTS=(...)` array so the forceful port-sweep backstop covers it too,
  not just the graceful PID-file kill.
- **`scripts/check_services.sh`** — add an HTTP health line:
  ```bash
  http_check "<Display Name>" "http://127.0.0.1:<port>/up"
  ```
  and, if it owns a database, a schema-depth line so a "process up but
  never migrated" state is caught:
  ```bash
  check_schema "<Display Name>" "$(db_url_for <db-name>)" "<repo-dir>/db/migrations"
  ```

A service that skips this step will start fine under `docker compose up`
but silently never appear in local `start_services.sh`/`check_services.sh`
runs — don't treat CI-green as proof this step was done.

## 9. CI & testing

Umbrella CI workflow (CI is centralized — services have no own workflows):

1. Add `./<name>/...` to the go vet list and the go test glob.
2. Add a `go build -o /dev/null ./<name>/cmd/<name>` step and a
   `docker build --check` line.
3. Add the compose services (§6) and their log-collection lines to the
   "collect logs on failure" step.

Tests: unit + feature suites in-repo (testcontainers for a throwaway
Postgres; `TESTCONTAINERS_RYUK_DISABLED=true` in CI). E2E: register the
service's endpoints in the E2E client's endpoint registry, add
`e2e_*.js` / `edge_*.js` scenarios tagged `@test-link [[atom]]`. If the
service sits behind the hub, the existing scenario suites passing
unchanged **is** the regression gate. Run one scenario locally rather than
the full suite when iterating.

## 10. OpenTelemetry (born instrumented — non-negotiable)

`observability.Setup("<name>")` at boot (OTLP export activates when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set), `otelgin` first in the middleware
chain, `otelpgx` via the kit's pool, W3C propagation via the kit's `httpx`
for outbound calls. The collector config is centralized — nothing
per-service to deploy.

## 11. Code health & change discipline

- The umbrella's code-health check must report zero errors for the new
  service: files ≤400 (warn) / 600 (error) effective LOC, nesting ≤4, every
  file 1–10 ATD links, `@spec-link` atop functions only (`@test-link` in
  tests).
- Docs move with code: update the port registry (§3) and any service-map
  doc in the same change that adds the service.

## Appendix — Extraction (splitting a domain OUT of the hub, not new-from-scratch)

Follow a strangler order:

1. **Kit & contracts first** (§1–§5) — service repo exists, dark, with
   settled atoms.
2. **Scaffold dark**: full service + own DB + tests + CI compose presence;
   nothing routes to it yet.
3. **Swap the client**: the caller keeps its domain interface, gains an
   httpx-backed client impl selected by config; the in-process impl stays
   available for one phase as a rollback flag. Convert any fire-and-forget
   call in a webhook/settlement path to a durable outbox job + idempotency
   key.
4. **Cut over routing** (public services only) + build read models for any
   SQL the caller used to run against the moved tables (denormalize; feed
   it with durable pushes).
5. **Drop dead weight**: remove the moved tables + the in-process impl from
   the caller; write the prod cutover runbook before touching prod.

Each phase lands with full CI (unit + scenario + edge suites) green before
the next starts.
