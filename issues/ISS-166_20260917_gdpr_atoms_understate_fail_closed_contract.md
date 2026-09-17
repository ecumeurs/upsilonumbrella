# Issue: GDPR export atoms omit the fail-closed guarantee and the tactical key-omission rule

**ID:** `20260917_gdpr_atoms_understate_fail_closed_contract`
**Ref:** `ISS-166`
**Date:** 2026-09-17
**Severity:** Low
**Status:** Open
**Component:** `upsilonauth/docs/service_gdpr_export_orchestrator.atom.md`, `upsilonapi/docs/api_profile_export.atom.md`, `upsilonapi/docs/rule_gdpr_compliance.atom.md`
**Affects:** ATD accuracy for the GDPR export; blocks STABLE promotion of the orchestrator atom

---

## Summary

ISS-118's post-task ATD sync verified the shipped export against its three governing atoms and
found the code correct but the **specification incomplete in three specific ways**. None of
these is a code defect — the implementation is right and reviewed. They are atom gaps, and
they were deliberately left unresolved because closing them means either writing new
specification text (a human call) or adding a link that was permission-blocked.

Both `service_gdpr_export_orchestrator` and `rule_gdpr_compliance` were advanced
**DRAFT → REVIEW** on verified link coverage. Neither went STABLE, because of gap 2.

---

## The three gaps

### 1. `api_profile_export` has no `@spec-link`, so it reports `NO_IMPL`

The atom's own `## TECHNICAL INTERFACE` requires *"`@spec-link [[api_profile_export]]` above the
public export route/handler."* No such tag exists anywhere in the tree.

The handler is `exportAccount` at `upsilonauth/internal/gateway/export.go:31`, registered at
`upsilonauth/internal/gateway/router.go:102`. It already carries `@spec-link` for
`upsilonapi:rule_gdpr_compliance` and `upsilonauth:service_gdpr_export_orchestrator` — the API
atom governing its own route is the one missing.

This is a **missing link, not drift**, so it is safe to simply add. The intended command:

```
atd update --spec-link upsilonapi:api_profile_export upsilonauth/internal/gateway/export.go
```

**Blocked:** the harness permission classifier denied this as "Modify Shared Resources". It was
not worked around. Needs a human to approve or apply it.

Note this atom is **doubly blocked** from REVIEW: it also lacks a `## EXPECTATION` section, one
of the ~30 ISS-164 instances. The two are entangled — fixing the link alone will not promote it.

### 2. The fail-closed *unconfigured* case is absent from all three atoms — and it is ISS-118's headline guarantee

All three atoms enumerate the incomplete-export triggers as a closed list of **four**: *"a
required downstream failure, malformed fragment, timeout, or unsupported registered service."*

The code has a **fifth**. `selectGDPRCollector` (`upsilonauth/cmd/upsilonauth/main.go:199`)
returns `UnavailableGDPRFragmentCollector` when `HUB_INTERNAL_URL` or `ECONOMY_INTERNAL_URL` is
unset, producing `incompleteFragment("export", "unavailable")` → `503 export_incomplete`.

This is the single most important behaviour ISS-118 delivered, and no atom specifies it. It is
arguably covered *in spirit* by the orchestrator's `## EXPECTATION` ("emitted only after every
required fragment succeeds"), but the enumerations read as exhaustive. Relatedly,
`selectGDPRCollector` — the decision point for the whole rule — carries **no `@spec-link` at
all**, despite the handler's own doc comment correctly describing the behaviour.

**This is why `service_gdpr_export_orchestrator` was held at REVIEW.** Promoting it to STABLE
would freeze a specification that omits its own main point.

### 3. The `tactical` key-omission rule is undocumented

`authv1.GDPRExport.Tactical` is `*battlev1.GDPRExportFragment` with `json:"tactical,omitempty"`,
so an account not registered to the game gets **no `tactical` key at all**, rather than a
zero-valued placeholder — a deliberate decision, since a zero-valued fragment in a legally
significant document would assert facts that are not true.

`api_profile_export` documents the neighbouring conventions ("empty retained datasets are
successful empty arrays and an absent wallet is null") but is silent on key omission.
`service_gdpr_export_orchestrator` only says "the MVP uses a typed battle/tactical fragment".
This is a consumer-visible contract detail with no atom covering it.

---

## Recommended Fix

1. Apply the `@spec-link` from gap 1 (needs permission approval).
2. Add the unconfigured-collector case to the incomplete-trigger enumeration in all three
   atoms, and tag `selectGDPRCollector` with a `@spec-link` to the orchestrator atom.
3. Add the `tactical` key-omission rule alongside the existing empty-array / null-wallet
   conventions in `api_profile_export`.
4. Only then consider `service_gdpr_export_orchestrator` for STABLE.

Steps 2 and 3 are specification writing, not reconciliation — the code is correct and must not
be changed to match the atoms. Draft the wording for human review before committing.

---

## Extra Data

Found during ISS-118's post-task ATD sync on 2026-09-17, by a manual atom-vs-code read.

The read was manual by necessity: `atd congruence` returned an unusable verdict
(`is_congruent: false` with an empty `audit_report` and no findings, exiting 0) and cannot
resolve a workspace-qualified target, as `congruence` and `trace` have no `--workspace` flag.
That verdict was discarded. Failure report filed at
`~/work/atd/failures/20260917_atd_congruence_empty_verdict_and_no_workspace_resolution.md`.

Cosmetic, not filed separately: `upsiloncli/tests/scenarios/e2e_gdpr_portability.js` writes its
atom tags unprefixed (`[[api_profile_export]]`) while sibling scenarios use the `upsilonapi:`
prefix. Both resolve today.

---

## References

- `upsilonauth/internal/gateway/export.go` (`exportAccount`, carries two of three spec-links)
- `upsilonauth/cmd/upsilonauth/main.go` (`selectGDPRCollector`, untagged)
- `issues/Ref_20260722_gdpr_export_per_game_gap.md` (ISS-118 — the work these atoms govern)
- `issues/ISS-164_20260916_expectation_section_gap_across_atom_corpus.md` (second blocker on `api_profile_export`)
