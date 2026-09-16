# Issue: ATD pre-commit orphan check reads `layer` only, ignoring `.atd`'s `OrphanExcludedTypes`, so it disagrees with `atd`'s own tooling

**ID:** `20260916_precommit_orphan_check_ignores_excluded_types`
**Ref:** `ISS-163`
**Date:** 2026-09-16
**Severity:** Medium
**Status:** Open
**Component:** `scripts/hooks/pre-commit`
**Affects:** `.atd` (`OrphanExcludedTypes` config), `atd crawl --gaps` (the tool this hook is meant to mirror), any atom whose `type` is in `OrphanExcludedTypes` (`MODULE`, `SPECIFICATION`, `USECASE`, `USER_STORY`) but whose `layer` is `ARCHITECTURE`/`IMPLEMENTATION` and `parents: []` — concretely `upsilonbattleui/docs/module_frontend.atom.md`

---

## Summary

`scripts/hooks/pre-commit` is a git hook (not yet installed into `.git/hooks` — it's a repo-tracked script meant to be `cp`'d in per its own header comment) that blocks a commit touching any staged `.atom.md` file whose `layer` is `ARCHITECTURE` or `IMPLEMENTATION` and whose `parents:` list is empty, on the theory that such an atom is an orphan. It decides this from `layer` alone. The project's own `.atd` config declares an `OrphanExcludedTypes` map (`MODULE`, `SPECIFICATION`, `USECASE`, `USER_STORY`) that exempts atoms of those `type`s from orphan treatment regardless of layer, and `atd`'s own tooling (verified via `atd crawl --gaps`) honours it. The bash hook does not check `type` at all, so it disagrees with the tool it is supposed to be a fast, zero-latency stand-in for. This was found during a repo-wide ATD structural audit on 2026-09-16; it was not fixed as part of that audit.

---

## Technical Description

### Background

The hook's own header comment states its purpose: "Ensures every ARCHITECTURE or IMPLEMENTATION atom staged for commit declares at least one parent, preventing orphaned lower-layer atoms." It is meant to be a fast, LLM-free, local stand-in for the orphan-detection logic that `atd`'s real tooling (e.g. `atd crawl --gaps`) implements. For that stand-in to be safe, its definition of "orphan" has to match the tool's — otherwise it can block commits `atd` itself considers fine.

`atd`'s definition takes more into account than raw `layer`: the root `.atd` config (`/home/bastien/work/upsilon/upsilon-hub/.atd`) declares:

```json
"OrphanExcludedTypes": {
  "MODULE": true,
  "SPECIFICATION": true,
  "USECASE": true,
  "USER_STORY": true
},
```

An atom of one of these `type`s is exempt from the orphan check regardless of `layer`. A `MODULE` atom is commonly a root aggregator by design — it has `dependents:` (children) but legitimately no `parents:`.

### The Problem Scenario

```
scripts/hooks/pre-commit (lines 20-24):

  LAYER=$(grep -E "^layer:" "$file" | awk '{print $2}' | tr -d '\r')
  PARENTS_COUNT=$(awk '/^parents:/ {flag=1; next} /^[^ -]/ {flag=0} \
                  flag && /-[[:space:]]+\[\[.*\]\]/ {print}' "$file" | wc -l)

  if [[ "$LAYER" == "IMPLEMENTATION" || "$LAYER" == "ARCHITECTURE" ]]; then
    if [ "$PARENTS_COUNT" -eq 0 ]; then
      echo "❌ ERROR: Orphaned Atom Detected -> $file"
      ...
      FAIL=1
    fi
  fi
  #  ^^^ TYPE is never read or checked against .atd's OrphanExcludedTypes.

.atd (root):

  "OrphanExcludedTypes": { "MODULE": true, "SPECIFICATION": true,
                            "USECASE": true, "USER_STORY": true }
  #  ^^^ atd's own tooling (atd crawl --gaps) honours this and does NOT
  #      flag a MODULE atom with empty parents as an orphan.
```

Concrete live example — `upsilonbattleui/docs/module_frontend.atom.md`:

```yaml
id: module_frontend
type: MODULE
layer: ARCHITECTURE
status: STABLE
parents: []
dependents:
  - [[module_frontend_board_ui_rendering]]
  - [[module_frontend_character_entity_creation]]
  - [[module_frontend_integration_constraint]]
  - [[module_frontend_matchmaking_orchestration]]
  - [[module_frontend_session_management]]
  - [[ui_dashboard]]
  - [[ui_landing]]
```

This is a legitimate root aggregator — 7 children in `dependents:`, no parent by design. Verified 2026-09-16:

```
$ atd crawl --gaps 2>&1 | grep -i module_frontend
(no output — atd does not flag it)
```

But because `layer: ARCHITECTURE` and `parents: []`, the bash hook's condition is true for this file; it WOULD print "❌ ERROR: Orphaned Atom Detected" and abort any commit that staged a change to it, with `FAIL=1` regardless of `atd`'s own verdict.

### Where This Pattern Exists Today

- `scripts/hooks/pre-commit` lines 20-32 — the `LAYER`/`PARENTS_COUNT` check; `TYPE` is never extracted from the file.
- `.atd` (repo root) lines ~24-29 — `OrphanExcludedTypes` declaration the hook ignores.
- `upsilonbattleui/docs/module_frontend.atom.md` — the concrete atom that would trip this today.
- A second script, `scripts/pre-commit.sh`, also exists in the same directory but is an unrelated CI-check runner (go vet/test/workspace sync) with no ATD/orphan logic; it is not implicated here.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | Medium — only fires when a commit happens to stage a change to an atom that is `ARCHITECTURE`/`IMPLEMENTATION`-layer, has an excluded `type`, and has empty `parents`; `module_frontend.atom.md` is the one confirmed live instance today, but any future `MODULE`/`SPECIFICATION`/`USECASE`/`USER_STORY` root aggregator has the same exposure |
| Impact if triggered | Low-Medium — commit is blocked with a misleading "orphaned atom" diagnosis; the suggested fixes in the hook's own error message ("add a parent" / use the `req_tech_debt_backlog` escape hatch) are both wrong for a legitimately parentless root aggregator, so a developer would either force a bogus parent link onto a clean atom or burn time investigating before realizing the hook, not the atom, is out of date |
| Detectability | Low until it fires — the hook is commit-scoped and this repo's copy is not installed into `.git/hooks` by default (per its own header, it requires a manual `cp`), so exposure depends on whether/where a given clone or CI step has it wired in; when it does fire, the mismatch versus `atd crawl --gaps` is the tell |
| Current mitigant | None — the hook is unconditional on `type`; `atd`'s own tooling being correct does not help because the hook does not call `atd`, it re-implements a narrower check in bash |

---

## Recommended Fix

**Short term:** Document the discrepancy (this issue) so anyone who hits a spurious block on a `MODULE`/`SPECIFICATION`/`USECASE`/`USER_STORY` root atom knows to check `.atd`'s `OrphanExcludedTypes` before trusting the hook's verdict, rather than adding a bogus parent link.

**Medium term:** Extend `scripts/hooks/pre-commit` to also extract each staged atom's `type:` field and skip the orphan check when that type is present (and `true`) in `.atd`'s `OrphanExcludedTypes`, so the bash hook and `atd crawl --gaps` agree on one definition of "orphan."

**Long term:** Consider having the hook shell out to `atd`'s own gap/orphan check (or an `atd`-exposed lint subcommand) instead of re-implementing a parallel, drift-prone heuristic in bash — one source of truth for orphan detection.

---

## Extra Data

Found during a repo-wide ATD structural audit run 2026-09-16, prompted by an unrelated earlier same-day incident where this exact class of surprise (a hook disagreeing with `atd`'s own model of validity) already cost real time on a different atom. Filed as documentation only; no hook or atom changes were made as part of filing this issue.

Verified commands (2026-09-16):
```
$ grep -n "OrphanExcludedTypes" .atd
24:  "OrphanExcludedTypes": {

$ atd crawl --gaps 2>&1 | grep -i module_frontend
(no output)
```

---

## References

- `scripts/hooks/pre-commit`
- `.atd` (repo root, `OrphanExcludedTypes`)
- `upsilonbattleui/docs/module_frontend.atom.md`
