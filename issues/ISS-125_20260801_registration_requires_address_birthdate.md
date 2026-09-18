# Issue: Registration requires full address and birth date — neither is needed for gameplay

**ID:** `20260801_registration_requires_address_birthdate`
**Ref:** `ISS-125`
**Date:** 2026-08-01
**Severity:** Medium
**Status:** Resolved
**Component:** `upsilonauth/internal/gateway/auth.go`, `upsilonbattleui/src/Pages/Auth/Register.vue`
**Affects:** `upsilonauth/internal/identity/identity.go`, `upsilonbattleui/docs/ui_registration_minimal_form_fields.atom.md`

---

## Summary

Registration currently mandates a full residential address (`full_address`) and a birth date (`birth_date`) on top of account name and password. Product direction (per user, 2026-08-01): neither field is of interest from the platform's point of view and the requirement should be removed. This is a deliberate scope reduction, not a defect — but it's codified as a STABLE architecture-layer ATD atom, so it needs a documented change, not just a code edit.

---

## Technical Description

### Background

`upsilonbattleui/docs/ui_registration_minimal_form_fields.atom.md` (status: STABLE, layer: ARCHITECTURE) currently states the intent as: "Requires strictly minimal information (Account Name, Password, Full Address, Birth Date) from the user" — i.e. address and birth date are explicitly named as part of the "minimal" required set.

### The Problem Scenario

- `upsilonbattleui/src/Pages/Auth/Register.vue:117-134` renders both fields as part of the registration form ("Full Residential Address" / "Birth Date"), with inline validation error display.
- `upsilonauth/internal/gateway/auth.go:267-274` enforces both as **required** on the register path via `requireString(body, "full_address", errs)` and `requireString(body, "birth_date", errs)` — a missing/empty value fails validation before an account can be created.
- Contrast with the update path (`auth.go:307-313`), which correctly treats both as optional (`optionalString`) — so the requirement is specifically a register-time gate, not a general schema constraint.
- Storage: `identity.go:108-109`'s `RegisterInput` has `FullAddress string` / `BirthDate time.Time` as non-pointer (mandatory) fields, vs `UpdateInput`'s pointer (optional) fields at `identity.go:117-118`.

### Where This Pattern Exists Today

- `upsilonauth/internal/gateway/auth.go:267-274` — required-field validation on register.
- `upsilonauth/internal/identity/identity.go:104-110` — `RegisterInput` struct shape.
- `upsilonbattleui/src/Pages/Auth/Register.vue:113-135` — form fields.
- `upsilonbattleui/docs/ui_registration_minimal_form_fields.atom.md` — the governing atom naming both fields as required.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | N/A — this is a confirmed current behavior, not a probabilistic risk |
| Impact if triggered | Medium — unnecessary PII collection (address, DOB) with no product use, plus registration friction |
| Detectability | High — visible on every registration attempt |
| Current mitigant | None; both fields are enforced today |

---

## Recommended Fix

**Short term:** None needed — this is scoped as a deliberate change, tracked here for follow-through.

**Medium term:**
1. Update `ui_registration_minimal_form_fields.atom.md` first (STABLE ARCHITECTURE atom — needs its INTENT/LOGIC revised to drop Full Address and Birth Date from the minimal set before the code changes, per ATD governance).
2. Switch `full_address`/`birth_date` from `requireString` to `optionalString` in `auth.go`'s register path (mirroring the update path), or remove them from the register payload/schema entirely if truly unused elsewhere (check `identitypg` schema/migrations and any downstream consumer — e.g. admin views — before dropping storage columns).
3. Remove or de-required the two fields from `Register.vue`.

**Long term:** If address/DOB have zero product use anywhere (no age-gating, no shipping, no localization logic keyed off them), consider dropping the columns from the `upsilonauth` schema entirely via a migration, rather than leaving unused PII at rest.
