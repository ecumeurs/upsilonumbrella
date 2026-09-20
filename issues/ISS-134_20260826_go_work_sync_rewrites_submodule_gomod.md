# Issue: `go work sync` rewrites submodule `go.mod`/`go.sum` on every CI run — committed manifests have drifted from what the workspace resolves

**ID:** `20260826_go_work_sync_rewrites_submodule_gomod`
**Ref:** `ISS-134`
**Date:** 2026-08-26
**Severity:** Medium
**Status:** Resolved
**Component:** `go.work`
**Affects:** `upsilonauth/go.mod`, `upsilonauth/go.sum`, `upsiloneconomy/go.mod`, `upsiloneconomy/go.sum`, `upsilonhub/go.mod`, `upsilonhub/go.sum`, `upsilontypes/go.mod`, `upsilontypes/go.sum`, `.github/workflows/ci.yml`, `scripts/run_ci_local.sh`

---

## Summary

`go work sync` — an existing step in both `.github/workflows/ci.yml` (`:35`, `:105`) and `scripts/run_ci_local.sh` — pushes the workspace's resolved dependency versions back down into each member module's own `go.mod`/`go.sum`. Running it today **modifies tracked files inside three submodules**: `upsilonauth`, `upsiloneconomy`, and `upsilonhub`. That it changes anything at all is the finding: the committed manifests in those three submodules no longer describe what the umbrella workspace actually builds against.

This was discovered incidentally while fixing ISS-132 (resolved; file removed 2026-08-27); it is unrelated to that change and pre-dates it.

---

## Technical Description

### Background

In a Go workspace, `go.work` + `go.work.sum` decide which version of each shared dependency every member module actually compiles against. Each module's own `go.mod`/`go.sum` can be out of step with that resolution and nothing will complain, because workspace mode simply doesn't consult them for version selection. `go work sync` is the command that reconciles the two — writing the workspace's answer back into each module.

### The Problem Scenario

From a clean tree (all 13 submodules reporting 0 dirty), a single `go work sync` produces:

```
upsilonauth   go.mod | 11 +++++-----   go.sum | 12 ++++++++++
  + github.com/riverqueue/river v0.40.0            <- promoted from indirect to DIRECT
  - github.com/exaring/otelpgx v0.11.1 // indirect
  - github.com/golang-migrate/migrate/v4 v4.19.1 // indirect
  - github.com/lib/pq v1.10.9 // indirect
  - github.com/riverqueue/river/riverdriver/riverpgxv5 v0.40.0 // indirect
  + github.com/tidwall/{gjson,match,pretty,sjson}, go.uber.org/goleak // indirect

upsiloneconomy   go.mod | 2 ++   go.sum | 36 ------------------------
  + go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.69.0 // indirect
  + golang.org/x/crypto v0.52.0 // indirect
  (go.sum loses 36 lines — the committed file carries stale surplus entries)

upsilonhub   go.mod | 9 +++++++++   go.sum | 12 ++++++++++
  + github.com/riverqueue/river v0.40.0            <- promoted from indirect to DIRECT
  + github.com/riverqueue/river/{riverdriver,rivershared,rivertype} v0.40.0 // indirect
  + github.com/tidwall/{gjson,match,pretty,sjson}, go.uber.org/goleak // indirect
```

`upsilonapi` and `upsilonplatform` are unaffected (0 dirty), so this is specific to the three services, not a workspace-wide condition.

**2026-09-19 re-validation:** Re-ran `go work sync` from a clean tree (0 dirty across all 13 submodules beforehand). The three original diffs reproduce verbatim — `upsilonauth`'s `river` indirect→direct promotion, and `upsiloneconomy`'s go.sum -36 — and a fourth submodule is now also affected:

```
upsilontypes   go.mod | 3 +++   go.sum | 5 ++++-
  + github.com/kr/pretty v0.3.1            // indirect
  + github.com/rogpeppe/go-internal v1.14.1 // indirect
  (go.sum: +4/-1 — adds github.com/kr/pretty, github.com/kr/text,
   github.com/rogpeppe/go-internal, and bumps gopkg.in/check.v1 from
   v0.0.0-20161208181325 to v1.0.0-20201130134442)
```

This affects `upsilontypes`, so the drift is now 4 of 13 submodules, not 3. Fix applied per the Recommended Fix below; see Change Log.

The `river` promotion is the clearest signal: `upsilonhub` runs the durable credit-award worker on River (`upsilonhub/internal/awards/`), and `upsilonauth` uses River migrations in its test harness — yet neither `go.mod` declares River as a direct requirement. It resolves today only transitively, via `upsilonplatform`'s `jobs` package.

### Why It Matters

1. **CI mutates tracked files on every run.** Both pipelines run `go work sync` before building. On an ephemeral GH runner this is invisible, but locally it leaves three submodules dirty after any CI run — which, among other things, makes `scripts/push_all.sh` refuse to push them (it declines on a dirty tree by design).
2. **Workspace-mode verification may not match image builds.** `go vet`/`go test` run in umbrella workspace mode, resolving via `go.work`/`go.work.sum`. The service Dockerfiles do NOT use the umbrella workspace — each runs its own `go work init` over a narrow subset (`upsilonauth/Dockerfile:21`, `upsiloneconomy/Dockerfile:22`, `upsilonhub/Dockerfile:35`) and then `go mod download` against the module's committed manifests. Two different resolution inputs means what CI tests and what ships in the image are not guaranteed to be the same build.
3. **`contract_upsilon_contract` requires sub-projects to remain independently buildable.** A `go.mod` that under-declares its module's real direct dependencies is drift against that clause, whether or not it currently happens to build.

### What Was NOT Verified

Honest scope limit — this issue reports an observed condition, not a proven failure:

- **Docker image builds have NOT been shown to break.** They evidently succeed today, presumably because the missing requirements resolve transitively through `upsilonplatform`. The risk described in point 2 is structural, not a reproduced failure.
- Whether committing the synced manifests is safe has not been tested — it may cascade into submodule CI, and each submodule is an independent repo with its own pipeline.
- Which commit introduced the drift was not bisected. The Phase 3/4/5 auth/economy extraction is the obvious suspect, given only the three extracted/refactored services are affected.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | High that the drift persists and grows; unknown that it causes a build/runtime divergence |
| Impact if triggered | Medium-High — a service image built against different dependency versions than the code CI verified |
| Detectability | Very Low — workspace mode never consults these files, so everything reports green |
| Current mitigant | Transitive resolution via `upsilonplatform` appears to cover the gaps today |

---

## Recommended Fix

**Short term:** Run `go work sync` once, review the resulting diffs, and commit the reconciled `go.mod`/`go.sum` in `upsilonauth`, `upsiloneconomy`, and `upsilonhub` — each in its own submodule commit. Verify each service's Docker image still builds afterward.

**Medium term:** Add a CI guard that fails the build if `go work sync` leaves the tree dirty (`git diff --exit-code` immediately after the existing sync step). That converts silent drift into a loud, immediate failure — the same principle applied to the module list in ISS-132.

**Long term:** Decide whether the service Dockerfiles should build against the umbrella workspace rather than reconstructing a narrow one, so image builds and CI verification share a single resolution source.

---

## References

- `.github/workflows/ci.yml:36,109` (the `go work sync` steps; step headers at `:35` and `:108`) — corrected 2026-09-19, was `:35,105`
- `scripts/run_ci_local.sh:218,266` (`stage_build`, `stage_unit`) — corrected 2026-09-19, line numbers added
- `upsilonauth/Dockerfile:18-26`, `upsiloneconomy/Dockerfile:19-27`, `upsilonhub/Dockerfile:25-44`
- `upsilonhub/internal/awards/` (River consumer), `upsilonplatform/jobs`
- Discovered during: ISS-132 (resolved; file removed 2026-08-27)
- Related: [ISS-123](ISS-123_20260724_host_side_ci_seed_scripts_superseded.md) — the same extraction produced host-script drift

---

## Change Log

- **2026-09-19**: Re-validated; confirmed still live and now affecting a fourth submodule, `upsilontypes` (see the re-validation note in Problem Scenario). Applied the short-term fix: ran `go work sync` once from the umbrella root; the reconciled `go.mod`/`go.sum` diffs in `upsilonauth`, `upsiloneconomy`, `upsilonhub`, and `upsilontypes` are left uncommitted in the working tree for review (per project rule, this agent does not commit). Verified with `go build`/`go vet` across the workspace (pre-existing, unrelated `upsilonauth/internal/economypurge` vet failure excluded — reproduced on unmodified `main` too) and real (non-`--check`) `docker build` runs of the `upsilonauth`, `upsiloneconomy`, and `upsilonhub` images, all of which succeeded. Applied the medium-term fix: added a "Verify Sync Left Tree Clean" guard step immediately after both `go work sync` steps in `.github/workflows/ci.yml`, and an equivalent `verify_sync_clean` check after both `go work sync` calls in `scripts/run_ci_local.sh`; both check the umbrella's own `go.work`/`go.work.sum` plus `git submodule foreach` over each submodule's `go.mod`/`go.sum`, and fail loudly (`die`/`exit 1` with a remediation message) rather than warn. Guard tested both ways locally (dirty tree fails naming the affected submodules; tree cleaned via `git stash` passes) before the fix diffs were restored. Long-term fix (Dockerfiles building against the umbrella workspace) remains undone, as scoped. Status set to `In Progress` pending user review/commit of the manifest diffs.
- **2026-09-20**: User reviewed and authorized commit. Reconciled manifests committed per-submodule (`upsiloneconomy` `eb2af6c`, `upsilonhub` `f6559ac`, `upsilontypes` `0e4601f`, plus `upsilonauth`'s manifest reconciliation folded into the ISS-137 fix commit `c764579`); the CI drift guard committed at umbrella `e363928`. Short and medium-term fixes are both now in the tree and verified starting from a clean, guarded state. Status set to **Resolved**. Long-term fix (Dockerfiles building against the umbrella workspace) is intentionally out of scope here — left as a candidate for a future issue if the dual-resolution risk (point 2 above) is ever observed to actually diverge.
