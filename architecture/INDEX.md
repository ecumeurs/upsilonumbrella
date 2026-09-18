# Architecture reference

Durable, forward-looking architecture references for the Upsilon platform. These
outlive any single work session — for the *current* code, the code and the ATD
atoms in `docs/` are always authoritative; these documents capture the shape,
rationale and operational procedures that the code alone does not spell out.

Session handoffs, phase-by-phase extraction design notes and the completed
battleui-migration process docs were removed after the v3 service extraction
landed (Phases 0–6 complete) — they had served their purpose. Their history
remains in git if ever needed.

| Document | What it is |
|---|---|
| [account_lifecycle.md](account_lifecycle.md) | The full account lifecycle across the extracted platform — creation, opt-in service/game enrollment, the `account_push` read-model sync, GDPR export (resolved, ISS-118) and GDPR erasure (open gap, ISS-165) — with the stage → owning service → fires/consumes map. |
| [architecture_anchor.md](architecture_anchor.md) | Current-state snapshot of the running system — the quick "what exists right now" anchor (cited by `.agent/rules/UPSILON.md`). |
| [platform_architecture.md](platform_architecture.md) | The v3 platform architecture: the four-game trajectory, world rules, service topology and the decisions behind them. |
| [service_map.md](service_map.md) | Canonical service → project ownership map, contract/vision attribution and the extraction status (cited by `CLAUDE.md` + `UPSILON.md`). |
| [platform_constraints.md](platform_constraints.md) | The non-negotiable platform constraints (SSE, pgx+sqlc, opaque tokens, durable jobs, injected clock, games-never-import-games …). |
| [observability.md](observability.md) | The platform-wide OpenTelemetry strategy and the current instrumentation state. |
| [how_to_add_a_service.md](how_to_add_a_service.md) | Step-by-step playbook for extracting or adding a new platform service (repo, DB, migrate/seed, S2S, CI, Caddy). |
| [prod_cutover_runbook.md](prod_cutover_runbook.md) | Reference procedure for adopting a single-DB deployment into the per-service topology — companion to the guarded `scripts/cutover_extraction.sh`. Reference only; never run (there is no production DB). |
| [property_key_vocabulary.md](property_key_vocabulary.md) | The frozen 64-key property vocabulary for the unified `property.Key` space: scope, kind, default-when-absent, composition rule and info level per key, plus the complete rename map. Specification for the `upsilontypes` registry. |
