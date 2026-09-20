# Upsilon — Universal Coding Standard

**Scope:** every Upsilon project — the umbrella and *all* submodules (`upsilonhub`,
`upsilonapi`, `upsilonbattleui`, `upsiloncli`, `upsilonbattle`, `upsilonmapmaker`, tooling, and
every service that spawns during v3.0). These rules are **transverse**: they hold regardless of
which repo, language, or layer you are in. They go **beyond ATD** (which governs *documentation
traceability*); this doc governs *how code is written and changed*.

> **Precedence.** ATD structure → [`.agent/rules/ATD.md`](.agent/rules/ATD.md). Project map →
> [`.agent/rules/UPSILON.md`](.agent/rules/UPSILON.md). Hub-specific operational specifics (which
> test scripts, `bin/` paths) → [`.agent/rules/COMMON.md`](.agent/rules/COMMON.md). **This file is
> the canonical source for the universal principles below**; where COMMON.md restates one, this
> file wins on the principle and COMMON.md wins only on hub-local mechanics.

The seven non-negotiables. Each is **MUST/NEVER**, not a preference.

## 1. ATD adherence

- **No business-layer code change without its ATD anchor.** Before altering a MECHANIC/REQUIREMENT
  behavior, the governing atom must exist and be settled. Follow the `atd-pre-code-change` flow.
- **One CONTRACT + one VISION atom per project** — not size-constrained, settled *before* any
  business atom of that project changes. A project never holds `contract_x` + `contract_y`; if two
  things need separate contracts, they are two projects.
- Every source file carries ≥1 ATD link (`@spec-link`/`@test-link`), atop the exact function/type —
  never on package/file headers. Test files use `@test-link` only. No phantom links.
- **Games never import games.** Cross-game influence flows only through platform state, shared
  vocabularies (item/effects/events), or the event bus — enforced by the import-boundary lint.

## 2. Observability — OpenTelemetry native, from day one

- **Every new service is born instrumented.** Greenfield instrumentation is near-free; retrofitting
  mature code is expensive. Do not defer it to "later."
- Instrument all three edges: **HTTP** (`otelgin`/`otelhttp`), **DB** (`otelpgx`), and **outbound
  clients** (`otelhttp` transport). Export **OTLP** to the shared collector.
- **Propagate W3C `traceparent`** across every service hop; map the existing `X-Request-ID` ⇄
  `traceparent` and record `upsilon.request_id` as a span attribute. Correlation must survive
  service boundaries (and the future HTTP→MQ swap, where it becomes message metadata).
- **Never call `time.Now()` directly and never spawn ad-hoc goroutines/tickers for scheduled work.**
  Time comes from the injected world clock (fakeable in tests); scheduled work goes through the
  durable job queue. This is what makes idle/narrative mechanics testable and restart-safe.
- **Known debt:** only `upsilonhub` is instrumented today; `upsilonapi` and the rest are not. New
  code does not add to that debt — instrument as you touch a service.

## 3. Crash early, fail fast

- **Defaulting hides critical errors.** No silent failures, no catch-all default values in core
  logic to "keep things running." A clear panic/rejection beats undefined behavior.
- Validate inputs at the boundary and reject the invalid loudly. Where garbage input can only mean a
  caller bug, let it surface (panic → recovery 500) rather than papering over it.
- Errors are values to handle or propagate, never to swallow. No empty `catch`/`_ = err`.

## 4. Strict contract adherence — no defaulting to save the day

- **Honor the API/interface contract exactly.** Do not invent fallbacks, coerce types, or fill
  missing fields to make a call "work." If the contract is violated, fail per the contract — do not
  rescue it with a guessed default. (Parity work is byte-level: reproduce the documented behavior,
  quirks included, rather than "improving" it silently.)
- The response **envelope** (`{request_id, message, success, data, meta}`) is a hard contract. Never
  modify serialization or the bridge/API contract without an explicit user-approved warning, and
  a matching update to `communication.md`, Postman, and the relevant ATD atoms.
- Cross-service references are **by UUID through the owning domain's interface** — never a reach
  across a seam (no cross-schema joins, no reading another domain's tables) to shortcut a contract.
- **DTOs must never use `any`/`interface{}` fields for input or output.** Every field must have a
  concrete type describing its structure.

## 5. Test-first when fixing bugs

- **Reproduce the error as a test before fixing it.** On any new bug, first write a test at the
  nearest concerned module that fails *because of* the bug. Only then make it pass. The test is the
  proof the bug existed and the guard that it stays dead.
- Tests exercise production code — **no test-only branches in production files** (rare observability
  exceptions only). Feature tests hit real dependencies; only external engines are doubled.
- Prefer targeted runs (`scripts/trigger_one_ci_test.sh`, unit suites) over the full destructive CI
  sweep; see COMMON.md for the hub's exact scripts.

## 6. Code health — zero-error standard

Enforced by `scripts/code_health_check.py`; treat its errors as blocking.

- **File size:** warn >400 effective LOC, error >600. Split along domain seams before trimming.
- **Nesting depth:** ≤4 levels; refactor beyond.
- **Doc density:** every function has an intent comment; missing docs on exported functions is an
  error. Match the surrounding file's comment density and idiom.
- **ATD density:** ≥1 link/file, ≤10 distinct atoms (warn >5 distinct); repeated links to the same
  atom count once. Bypass tokens (`@lint-ignore-*`) are for genuine exceptions (third-party/generated
  code), not for silencing your own.

## 7. Change discipline

- **Docs move with code.** Any change to an API path/payload/behavior updates `communication.md`,
  Postman, and the ATD atom in the same change. Observability and contracts docs likewise.
- **Documentation is self-sufficient — no external references.** No doc (in-code comment, README,
  `communication.md`, ATD atom, architecture doc, anything under `.agent/`) may point a reader at
  issues, failure reports, tickets, PRs, chat threads, or other out-of-band material to understand
  it. A doc must stand on its own for whoever reads it next, without chasing a link that may be
  stale, private, or gone. The only exception is a **hard link between parts of the same split
  document** (an index linking to its subject files, a subject file linking back to its index) —
  never a link out to a different kind of artifact.
- Commit/push only when asked; branch off the default branch first. Binaries go to `bin/` (git-
  ignored), never committed.
- **New features and major updates start in a new git worktree**, not the checked-out working
  copy. Isolates in-progress feature/refactor work from whatever else is live in the primary
  checkout, and keeps the umbrella + submodule tree clean for concurrent work. Small fixes and
  targeted bug patches don't need one — use judgment on "major."
- Report outcomes faithfully — if a test fails or a step was skipped, say so with the evidence.

---

*When in doubt: crash loud, honor the contract, write the test first, keep the trace flowing, and
anchor it in ATD. If a rule seems to force worse code, raise it with the user — do not quietly
route around it.*
