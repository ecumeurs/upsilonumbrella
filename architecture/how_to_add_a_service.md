# How to Add a Service to the Upsilon Platform

**Status:** Living document, born from the upsilonauth/upsiloneconomy extractions (2026-07-22).
Every step below was actually exercised; when you add a service, follow the order — it is
dependency-ordered, and each stage leaves the umbrella CI green.

A "service" here is a standalone Go process in its own repo/submodule, with its own database,
assembled from the shared kit (`upsilonplatform`). Reference implementations: **upsilonauth**
(public-facing + internal surface) and **upsiloneconomy** (internal-only). Copy from them, not
from memory.

---

## 0. Decide the seams first (architecture gate)

Before any repo exists, answer in writing (an update to `service_map.md` or an extraction doc):

- **What does it own?** Tables, invariants, vocabulary. One sentence per table.
- **Public or internal?** Public services get a Caddy route on the front door (`:8085`);
  internal services are only reachable service-to-service and `/internal/*` is black-holed
  at the proxy. Prefer internal — the hub composes the public API.
- **What crosses the boundary?** Cross-service references are **UUIDs only** — no foreign
  keys, no SQL joins across services, ever. Ownership checks go through the owning service's
  API. If today's code joins across the future seam, plan the read model or RPC first.
- **Sync or durable?** User-facing calls are synchronous RPC. Anything fired from a
  settlement/webhook/background path must be a durable River job on the caller side plus an
  idempotency key enforced by the callee (see the award pipeline).
- **Does it store personal data?** If any table holds data attributable to an account, the
  service owes a GDPR export fragment (§7) and a purge path before it goes live. Answer this
  now, in writing — retrofitting portability after cutover is exactly how ISS-118 happened.

## 1. ATD governance (before any code)

1. Create the repo's `docs/` with **exactly one** `contract_<name>.atom.md` (type CONTRACT)
   and **one** `vision_<name>.atom.md` (type VISION), layer BUSINESS, parents
   `[[shared:contract_upsilon_contract]]` / `[[shared:vision_upsilon_vision]]`. Settle them
   **before** any business atom or business code — that is the platform rule (ATD.md §1.4).
2. Copy the `.atd` config from an existing service repo.
3. Register the project in the umbrella `.atd.workspace` (`{"name": "<name>", "path": "<name>"}`).

## 2. Repo + git integration

```bash
gh repo create ecumeurs/<name> --private --description "..."
# scaffold: README.md, go.mod (module github.com/ecumeurs/<name>, go 1.25.0),
#           .gitignore (bin/, *.log, .env), .atd, docs/  → commit, push
cd <umbrella> && git submodule add ../<name>.git <name>
```

- Submodule URLs are **relative** (`../<name>.git`) — they resolve against the umbrella origin.
- Add `./<name>` to the umbrella `go.work` `use` block. No `replace` directives — the
  workspace wires local source; run `go work sync` afterwards and expect go.mod/go.sum
  churn in sibling modules (dependency graph unification — commit it, it keeps standalone
  builds reproducible).
- Commit order is always **submodule first, then umbrella pointer bump**; verify with
  `./scripts/repo_status.sh`.

## 3. Service shell (the shape every service shares)

```
cmd/<name>/main.go       serve (default) | -migrate | -seed | -healthcheck
internal/config/         crash-early Load(): <NAME>_ADDR (default :<port>), DATABASE_URL
                         (mandatory), S2S_TOKEN (mandatory if it has an internal surface),
                         APP_DEBUG, OTEL_SERVICE_NAME (default "<name>")
internal/<domain>/       domain package — MUST NOT import net/http (transport isolation)
internal/api/            HTTP handlers (Gin), envelope + middleware from the kit
db/migrations/ + embed.go  golang-migrate SQL, embedded
sqlc.yaml                sqlc codegen against the migrations
Dockerfile               see §6
docs/ .atd               see §1
```

Use the **`upsilonplatform` kit — never copy its code**: `respond` (envelope),
`middleware` (envelope unwrap + error→envelope + recovery), `clock` (injected — `time.Now()`
is forbidden in domain/gateway code), `observability` (OTel setup), `database`
(pgxpool + otelpgx + migrate helpers taking your `embed.FS`), `jobs` (River, only if the
service has background work), `httpx` (S2S client — see §7).

Router chain, in this exact order (parity with the hub):
`otelgin.Middleware(serviceName)` → `SetDebug` → `middleware.Envelope()` →
`observability.RequestIDSpanAttribute()` → error/recovery middleware. Health: `GET /up`
(envelope-free). The `-healthcheck` flag self-probes `/up` and exits 0/1 — required because
the runtime image is distroless (no shell for compose healthchecks).

Port registry (extend it here when you claim one): 8081 upsilonapi · 8085 Caddy front door ·
8090 upsilonhub · **8091 upsilonauth** · **8092 upsiloneconomy** · 5173 Vite dev ·
5433→5432 Postgres · 4317/4318 OTel collector.

## 4. Database (one database per service)

- Every service owns **its own database** on the shared Postgres instance —
  `postgres://…/<name>` — so it can move to a dedicated instance later without SQL changes.
  Never point two services at one database; never query another service's database.
- Add the `CREATE DATABASE` block to `deploy/initdb/create_databases.sql` (idempotent
  `\gexec` pattern). It runs on first cluster init: CI is always fresh; an existing **dev**
  volume needs `docker compose down -v` once.
- Migrations: golang-migrate, embedded, run by your own `-migrate` mode (plus
  `jobs.Migrate` for River if you use jobs). Seed via `-seed`.
- **Seed determinism:** cross-service fixtures agree on ids because every seeded row uses
  `upsilontypes/seedids` (UUIDv5 of a stable name) — auth seeds accounts, economy seeds the
  catalog, the hub seeds gameplay against the same ids, in any order.

## 5. Wire contracts

- DTOs are **plain structs** in `upsilontypes/<name>v1` (transport isolation: no HTTP types).
  They are the frozen contract; version by adding packages (`<name>v2`), not by breaking fields.
- All payloads travel inside the standard envelope `{request_id, message, success, data, meta}` —
  byte-parity is a hard contract, which is why the envelope lives in the kit.

## 6. Docker

- Dockerfile with **build context = umbrella repo root**: copy `go.work` + every module's
  `go.mod`, `go mod download`, copy source, build only your module; final stage
  `gcr.io/distroless/static-debian12:nonroot`, binary at `/app/<name>`, `EXPOSE <port>`.
  Add a `Dockerfile.dockerignore`.
- Compose (`docker-compose.ci.yaml`, mirrored in prod compose at cutover): a
  `<name>-migrate → <name>-seed → <name>` chain hanging off `db: service_healthy`, with
  healthcheck `[ "CMD", "/app/<name>", "-healthcheck" ]`. Same image, different args.
- **Adding a module to `go.work` breaks OTHER images until you touch them** (learned the
  hard way, 2026-07-22). Three context strategies coexist:
  1. *Full-workspace copy* (upsilonapi, upsiloncli): they `COPY go.work` + **every** module's
     `go.mod` — your new module's `go.mod` must be added to their COPY lists or their
     `go mod download` fails.
  2. *Minimal `go work init`* (upsilonhub, upsilonauth, upsiloneconomy): immune to go.work
     growth, but if a service starts importing your module, add it to that Dockerfile's
     COPY + `go work init` list. Mind transitive private deps: pulling in `upsilontypes`
     drags `upsilonmapdata`/`upsilontools` (pseudo-versioned private repos) into the
     workspace too.
  3. *Per-Dockerfile ignore allowlists* (`<svc>/Dockerfile.dockerignore` with `*` + `!dirs`):
     any newly needed directory must ALSO be un-ignored there, or COPY fails with
     `"/<dir>": not found`.
  After any workspace change, rebuild **all** images (`docker compose -f docker-compose.ci.yaml
  build`) before trusting the stack.

## 7. Service-to-service calls & security

- Callers use `upsilonplatform/httpx`: per-service base URL from config, `WithInternalToken`
  (sent as `X-Internal-Token`), default 5s timeout, GET-only bounded retries, otelhttp
  transport (traceparent propagates automatically), `X-Request-ID` carried from context.
- Callees guard `/internal/v1/*` with a middleware comparing `X-Internal-Token` via
  `crypto/subtle.ConstantTimeCompare`; failure → 401 envelope.
- The front door must never expose internal surfaces: Caddy `respond /internal/* 404`.
- Auth of end users is upsilonauth's monopoly: validate bearers via its introspection
  endpoint (with a short-TTL cache), never by reading its database.

### GDPR export fragment (mandatory if the service stores personal data)

upsilonauth is the GDPR authority and owns the only public export route
(`GET /api/v1/auth/export`). It does not read your database — it composes fragments. A
service holding personal data MUST ship, before go-live:

- `GET /internal/v1/gdpr/export/{user_id}`, behind the same `X-Internal-Token` fence as every
  other internal route, returning a typed, versioned DTO (`schema_version`, e.g.
  `battlev1.gdpr-export.v1`) owned by the service and published in `upsilontypes`.
- **Owner-scoped queries only.** The fragment contains that user's data and nothing else —
  no other account's rows, no secrets, no credentials, no third-party personal data.
- **No internal account UUID in anything that reaches the public payload**
  (`requirement_customer_user_id_privacy`): the UUID scopes the query, it is not export content.
- Registration in auth's collector so the aggregate picks the fragment up.

The aggregate is **fail-closed**: auth returns `200` only when every required fragment was
obtained, because a `200` is a completeness claim in a legally significant document. A
fragment that is unreachable or unimplemented fails the whole export with `503
export_incomplete` — it never degrades to a silent partial success. An *empty* owned dataset
is a successful empty fragment; an *absent* one is a failure. Get this distinction right in
your handler.

## 8. CI & testing

Umbrella `.github/workflows/ci.yml` (CI is centralized — services have no own workflows):
1. Add `./<name>/...` to the **go vet** list and the **go test** glob.
2. Add a `go build -o /dev/null ./<name>/cmd/<name>` step and a `docker build --check` line.
3. Add the compose services (§6) and their log-collection lines in "Collect Docker Logs on Failure".

Tests: unit + feature suites in-repo (testcontainers for a throwaway Postgres;
`TESTCONTAINERS_RYUK_DISABLED=true` in CI). E2E: register the service's endpoints in
`upsiloncli/internal/endpoint/`, add `e2e_*.js` / `edge_*.js` goja scenarios under
`upsiloncli/tests/scenarios/` tagged `@test-link [[atom]]`. If the service sits behind the
hub, the existing scenario suites passing unchanged **is** the regression gate. Run one
scenario locally with `scripts/trigger_one_ci_test.sh <name>` (never `trigger_all_ci_tests.sh`).

## 9. OpenTelemetry (born instrumented — non-negotiable)

`observability.Setup("<name>")` at boot (OTLP export activates when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set), `otelgin` first in the middleware chain, `otelpgx`
via the kit's pool, W3C propagation via the kit's httpx for outbound. The collector config
lives at `upsilonhub/deploy/otel-collector.yaml`; nothing per-service to deploy.

## 10. Code health & change discipline

- `python3 scripts/code_health_check.py <name>` must report zero errors: files ≤400 (warn)
  /600 (error) effective LOC, nesting ≤4, every file 1–10 ATD links, `@spec-link` atop
  functions only (`@test-link` in tests).
- Docs move with code: update this file, `service_map.md`, and the port registry in the
  same change that adds the service.

---

## Appendix A — Extraction (splitting a domain OUT of the hub)

The identity/economy extractions followed a strangler order; reuse it:

1. **Kit & contracts first** (this doc §1–§5) — service repos exist, dark, with settled atoms.
2. **Scaffold dark**: full service + own DB + tests + CI compose presence; nothing routes to it.
3. **Swap the client**: the hub keeps its domain interface, gains an httpx-backed client impl
   selected by config; in-process impl stays one phase as a rollback flag. Convert any
   fire-and-forget call in a webhook/settlement path to a River outbox job + idempotency key.
4. **Cut over routing** (public services only) + build hub-side read models for any SQL the
   hub used to run against the moved tables (denormalize; feed it with durable pushes).
5. **Drop dead weight**: hub migration removes moved tables + the in-process impl; write the
   prod cutover runbook before touching prod.

Each phase lands with the full CI (unit + scenario + edge suites) green.

<!-- Phases 3-6 of the 2026-07 extraction will refine Appendix A with what actually happened. -->
