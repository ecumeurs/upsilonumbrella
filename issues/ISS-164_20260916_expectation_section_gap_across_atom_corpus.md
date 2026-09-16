# Issue: 77 atoms across eight projects have no usable `## EXPECTATION` section — 29 as empty stubs, 48 absent entirely

**ID:** `20260916_expectation_section_gap_across_atom_corpus`
**Ref:** `ISS-164`
**Date:** 2026-09-16
**Severity:** Medium
**Status:** Open
**Component:** atom corpus (umbrella-root `docs/` + seven submodule `docs/` trees)
**Affects:** `atd lint` (every project below reports findings), ATD's verification phase, the atom template/scaffolding that emits section headings

---

## Summary

`atd lint` reports "Missing mandatory section: ## EXPECTATION" for 77 atoms spread
across eight projects. Investigation on 2026-09-16 showed this single lint message
is actually covering **two distinct defects**, which matters because they have
different causes and different fixes:

- **29 atoms have the `## EXPECTATION` heading present but completely empty** — the
  heading is the last line of the file with no body beneath it. The scaffolding
  emitted the section; nobody ever filled it in.
- **48 atoms have no `## EXPECTATION` heading at all.**

The four most recently authored projects — `upsilonauth`, `upsiloneconomy`,
`upsilonhub`, `upsilonplatform`, i.e. the Phase 3–6 extracted services — are
**completely clean** (0 findings each). The gap is concentrated entirely in the
older corpus. This is legacy authoring debt, not an actively regressing template.

Filed as documentation only; no atoms were edited.

---

## Technical Description

### Background

`## EXPECTATION` is where an atom states what must observably hold if it is
correctly implemented — it is the anchor ATD's verification phase and `@test-link`
traceability hang off. An atom without one asserts intent and interface but offers
nothing to verify against, so it cannot participate meaningfully in the
Discovery → Specification → Implementation → **Verification** lifecycle.

### Measured distribution (2026-09-16)

Counts are `atd lint <docs>` run from inside each project (verified identical when
run from the umbrella root, so the per-project `.atd` config is not a factor):

| Project | Atoms flagged |
|---|---|
| `upsilonbattle/docs` | 26 |
| `upsilonbattleui/docs` | 16 |
| `upsilontypes/docs` | 15 |
| `docs` (umbrella root) | 12 |
| `upsiloncli/docs` | 2 |
| `upsilonmapdata/docs` | 2 |
| `upsilonmapmaker/docs` | 2 |
| `upsilontools/docs` | 2 |
| **Total** | **77** |
| `upsilonauth`, `upsiloneconomy`, `upsilonhub`, `upsilonplatform` | 0 — clean |

Split by defect type across those same eight projects:

```
heading present but EMPTY: 29
heading ABSENT entirely  : 48
```

### The empty-stub case

`upsiloncli/docs/contract_cli_contract.atom.md` ends:

```
- **Related Atoms:** `[[shared:contract_upsilon_contract]]`

## EXPECTATION
```

The heading is the final line; there is no body. A plain `grep '^## EXPECTATION'`
finds it, which is why a superficial check disagrees with `atd lint` — lint is
correctly requiring content, not just a heading. Anyone auditing this with grep
will conclude the corpus is fine when it is not.

For contrast, `upsilonauth/docs/contract_auth_service.atom.md` passes with a real
assertion:

> Any client presenting a valid opaque token to any Upsilon service is authenticated
> by this service's judgment alone; revoking here locks the whole platform within the
> cache bound, and no auth behavior observable before the extraction changes byte-wise
> after it.

That is the standard the 77 should be brought to.

### Secondary findings in the same audit

Recorded here rather than filed separately, as they are the same backfill pass:

- `upsilontypes:rule_item_pricing_simple` — also missing `## TECHNICAL INTERFACE`.
- `upsilonbattle:mech_controller_behavior` — missing `## INTENT`.
- Several `upsilonbattle` atoms — missing `priority`.
- `mechanic_battle_engine_stress_testing` (umbrella root) — has a `@spec-link` in
  the implementation but 0 `@test-link`s (traceability gap, distinct from this
  issue but surfaced by the same lint run).

### Explicit scope exclusions

Both by direct maintainer ruling on 2026-09-16, and both excluded from the 77:

- **`upsilonapi`** — old, and under separate rework/evaluation (see ISS-162) which
  owns its atoms, including known CONTRACT/VISION staleness still asserting a
  Laravel gateway and JWTs.
- **`upsilonaws`** — deployment tooling, removed from ATD entirely in the same
  session, as CI/tooling/deployment fall outside ATD's business-only scope.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | Certain — already present, 77 confirmed instances |
| Impact if triggered | Medium — atoms without a verifiable expectation silently weaken ATD's central promise; a `@test-link` has nothing specific to prove, and reviewers cannot tell "verified" from "asserted". Concentrated in the oldest, least-recently-reasoned-about corpus, which is where it is least likely to be noticed |
| Detectability | High once looked for (`atd lint` reports it per project) — but **low by casual inspection**, because 29 of the 77 have the heading and pass a naive grep |
| Current mitigant | None. Lint reports it; nothing enforces it at commit time, and the pre-commit hook checks orphaning only (see ISS-163) |

---

## Recommended Fix

**Short term:** This issue — record the real numbers and the empty-vs-absent split
so nobody re-audits with grep and concludes the corpus is clean.

**Medium term:** A dedicated backfill pass, project by project, smallest first
(`upsiloncli`/`upsilonmapdata`/`upsilonmapmaker`/`upsilontools` are 2 each and are
cheap wins that also establish the house standard). Treat the 29 empty stubs as the
higher priority: the heading already promises content that is not there. This is
atom-authoring work, so it belongs with `documentalist`, and it must not be done by
generating filler — an expectation that restates the intent is worse than none.

**Long term:** Once the corpus is clean, consider extending the ATD pre-commit hook
to reject a staged atom whose `## EXPECTATION` is absent or empty, so the gap cannot
reopen. Note ISS-163 first: the hook currently re-implements ATD rules in bash and
already drifts from `atd`'s own model, so adding a second rule there compounds that
problem unless the hook is reworked to delegate to `atd`.

---

## Extra Data

Found during a repo-wide ATD structural audit on 2026-09-16, run alongside the work
that retired the dead Laravel gateway atoms and removed ATD from `upsilonaws`. The
empty-vs-absent distinction was discovered only because a `grep` cross-check
contradicted `atd lint` on `upsiloncli:contract_cli_contract`, which initially looked
like a lint false positive and turned out to be the opposite.

Verification commands (2026-09-16):

```
$ for p in upsilonbattle upsilonbattleui upsilontypes upsiloncli \
           upsilonmapdata upsilonmapmaker upsilontools; do
    (cd $p && atd lint docs 2>/dev/null | grep -c "## EXPECTATION")
  done
26 16 15 2 2 2 2
$ (cd upsilonauth && atd lint docs | grep -c "## EXPECTATION")
0
```

---

## References

- `atd lint <docs>` per project
- `upsiloncli/docs/contract_cli_contract.atom.md` (empty-stub example)
- `upsilonauth/docs/contract_auth_service.atom.md` (correctly authored contrast)
- ISS-163 (pre-commit hook drift — prerequisite for any hook-level enforcement)
- ISS-162 (`upsilonapi` rework — owns that project's excluded atoms)
