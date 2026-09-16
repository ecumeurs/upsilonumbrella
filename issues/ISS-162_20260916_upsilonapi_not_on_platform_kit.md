# Issue: upsilonapi predates the platform kit — no OTel, no shared plumbing, and its name no longer fits

**ID:** `ISS-162_20260916_upsilonapi_not_on_platform_kit`
**Ref:** `ISS-162`
**Date:** 2026-09-16
**Severity:** Medium
**Status:** Open
**Component:** `upsilonapi/go.mod`
**Affects:** `upsilonhub` (engine caller), `upsiloncli` (E2E driver), `upsilonbattle` (domain rules consumed by the engine)

---

## Summary

`upsilonhub`, `upsilonauth`, and `upsiloneconomy` all compose on `upsilonplatform` (`clock`/`database`/`httpx`/`jobs`/`observability`/`respond`) and are OTel-instrumented end to end. `upsilonapi` — the battle engine bridge (`:8081`) — predates that extraction and was never ported: its `go.mod` has no `upsilonplatform`, no `pgx`, no `otelgin`/OTLP wiring, nothing. It's the one backend process left running on ad-hoc Gin plumbing instead of the shared kit. Separately, as the platform grows toward more game modules (tycoon/spy/digital, each getting its own engine bridge per `architecture/service_map.md`), the name `upsilonapi` stops being descriptive — it should probably become `upsilonbattleapi` to mirror `upsilonbattle`/`upsilonbattleui` and leave room for sibling engine bridges.

---

## Technical Description

### Background

Per `architecture/observability.md`, every platform-kit service is "born OTel-instrumented" by composing on `upsilonplatform`: `otelgin` middleware, OTLP export, `traceparent` propagation, `X-Request-ID` mapping. `upsilonapi` sits outside that — it's a thin Gin JSON bridge (`gin` + `uuid` + `logrus` + `testify` only, per its `go.mod`) that hub calls in-process/network for match state and engine callbacks, with none of the shared observability, database, or S2S-client plumbing.

### The Problem Scenario

```
upsilonhub (platform kit, OTel spans) ──HTTP──▶ upsilonapi (:8081, bare Gin)
     │                                                │
  otelhttp client span emitted                   no otelgin middleware
  traceparent header sent                        header dropped, no child span
     │                                                │
     ▼                                                ▼
  trace shows hub ──▶ [gap] ──▶ engine work invisible in the collector
```

1. A request enters via the hub, which emits a client span (`otelhttp` per `architecture/observability.md` line 24) and forwards `traceparent`.
2. `upsilonapi` has no `otelgin`/OTLP wiring to receive that context or emit its own spans.
3. Every trace that touches the battle engine has a blind spot exactly where match logic runs — the highest-value segment to observe.
4. Meanwhile `upsilonauth`/`upsiloneconomy` show the target shape is well understood (both went `repo:*` scaffold → `upsilonplatform` composition → Caddy cutover) but nothing tracks doing the same for `upsilonapi`.

### Where This Pattern Exists Today

- `upsilonapi/go.mod` — no `upsilonplatform`, no `go.opentelemetry.io/*`, no `pgx`. Compare `upsilonauth/go.mod`, which pulls `upsilonplatform`, `pgx/v5`, and `otelgin`.
- `architecture/observability.md:24,28,51,76` — explicitly flags `upsilonapi` as the one unregistered OTLP emitter ("`ENG -.OTLP TODO.-> OTEL`" in the topology diagram) and names it as future work, with no owning issue.
- `architecture/service_map.md` §1 — table row for `upsilonapi` marks OTel as "❌ not instrumented (design exists, doc 04)"; §3 previews future game engines (tycoon/spy/digital) that would need their own bridges, which is where the naming collision starts to matter.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | High — every battle match currently exercises this gap, not a rare path |
| Impact if triggered | Medium — no data loss, but tracing blind spot on the exact component (engine) most useful to observe; also blocks S2S conventions (traceparent, `X-Internal-Token`, `X-Request-ID`) that every other service already has via `upsilonplatform/httpx` |
| Detectability | Low — nothing fails loudly; it just silently doesn't show up in the collector, and only doc comments (`observability.md`) currently track the gap |
| Current mitigant | None functional — `upsilonapi` works today, it's just unobserved and off the shared kit. Caddy/private networking limits blast radius (see `ISS-117`) but does not address instrumentation |

---

## Recommended Fix

**Short term:** File this issue (done) and cross-reference it from `architecture/observability.md`'s `upsilonapi` TODO markers so the doc note has a tracked owner instead of floating prose.

**Medium term:** Port `upsilonapi` onto `upsilonplatform` the same way `upsilonauth`/`upsiloneconomy` were extracted: adopt `observability` (otelgin + OTLP export), `httpx` (S2S client conventions) for its hub-facing calls, and `respond` for envelope parity, following the `architecture/how_to_add_a_service.md` playbook. This closes the tracing gap without a rename.

**Long term:** Decide and execute the `upsilonapi` → `upsilonbattleapi` rename (repo rename, module path, all references in `CLAUDE.md`/`UPSILON.md`/`architecture/service_map.md`/`docker-compose.yaml`/CI configs) once — ideally bundled with the platform-kit port so consumers update both at once rather than twice. Worth doing before tycoon/spy/digital spin up their own engine bridges and `upsilonapi` becomes ambiguous by comparison.

---

## Extra Data

Confirmed via `go.mod` diff: `upsilonapi` has zero `upsilonplatform`/OTel/`pgx` dependencies where `upsilonauth` has all three. No existing issue covers this — `issues --search upsilonapi` and `issues --search "platform kit"` turned up nothing on point (`ISS-117` is an unrelated Dependabot-vuln issue on the same repo).

---

## References

- `upsilonapi/go.mod` vs `upsilonauth/go.mod`
- `architecture/observability.md:24,28,51,76`
- `architecture/service_map.md` §1, §3
- `architecture/how_to_add_a_service.md` (extraction playbook)
- `CLAUDE.md` §1 (service roster, port mappings)
