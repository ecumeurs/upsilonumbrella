# Issue: Admin User Registry Leaks `full_address`/`birth_date` in Plaintext

**ID:** `20260712_admin_users_endpoint_leaks_private_fields`
**Ref:** `ISS-116`
**Date:** 2026-07-12
**Severity:** Medium
**Status:** Resolved
**Component:** `upsilonhub/internal/gateway/resources.go` (`userJSON`/`newUserJSON`)
**Affects:** `GET /api/v1/admin/users` (`admin.go:44`), `POST /api/v1/admin/users/{account_name}/anonymize` pre-anonymize response (`admin.go:90`); `upsiloncli/tests/scenarios/edge_admin_private_data_access.js` (EC-49, ISS-107 audit)

---

## Summary

`rule_admin_access_restriction` (`upsilonapi`) documents: *"Administrators
MUST NOT have access to `full_address`/`birth_date` fields of users...
Dashboard and API responses for administrators must censor or omit these
fields, even when managing user accounts."* No code anywhere in the hub
implements this censorship. `newUserJSON` (`resources.go:55`) is a single,
context-blind serializer reused for self-profile, login, **and** the admin
registry/anonymize responses — it always includes the raw `full_address`
and `birth_date` values. Verified live: registering a user with
`full_address: "999 Secret Lane"` and then calling
`GET /api/v1/admin/users` as the seeded admin returns that exact string in
the listing. The one code path spec-linked to this atom
(`RequireAdmin()` middleware, `middleware/auth.go:90`) enforces a completely
different rule (who may reach `/admin/*` routes at all) — it has no
connection to field-level censorship, so the atom is spec-linked to the
wrong logic and its real content has **zero** enforcing code.

---

## Technical Description

### Background

`entity_player`'s private fields (`full_address`, `birth_date`) are meant to
be visible to the owning user (self-profile) but hidden from administrators
browsing the user registry — a data-minimization rule distinct from (and
easily confused with, see Extra Data) `RequireAdmin()`'s route-level
authorization gate.

### The Problem Scenario

```
1. Player registers with full_address="999 Secret Lane", birth_date=1990-01-01.
2. Admin logs in (admin_login) and calls GET /api/v1/admin/users.
3. Response items[] includes the player's record with the raw, uncensored
   full_address and birth_date — same shape newUserJSON produces for the
   owner's own profile_get.
```

Reproduced live via curl (bypassing the CLI harness) on 2026-07-12:

```
$ curl -s http://127.0.0.1:8090/api/v1/admin/users?search=auditcheck_iss103 \
    -H "Authorization: Bearer <admin token>"
{"data":{"items":[{"account_name":"auditcheck_iss103", ...,
  "full_address":"999 Secret Lane","birth_date":"1990-01-01", ...}]}}
```

Same leak occurs on the `anonymize` endpoint's pre-mutation read path if a
caller inspects a non-anonymized target, and on any future admin-facing
consumer of `newUserJSON`.

### Where This Pattern Exists Today

- `upsilonhub/internal/gateway/resources.go:18-30` — `userJSON` struct
  carries `FullAddress`/`BirthDate` unconditionally, no admin/owner
  distinction.
- `upsilonhub/internal/gateway/resources.go:55-73` — `newUserJSON(u, roster)`
  has no parameter or caller-context to select a censored variant.
- `upsilonhub/internal/gateway/admin.go:44-58` (`users()`, list) and `:90`
  (`anonymize()`, response) both call `newUserJSON(u, nil)` directly — same
  serializer as `profile.go:37`'s self-view and `auth.go:74/108/134`'s
  login/register responses.
- `upsilonhub/internal/gateway/middleware/auth.go:90` —
  `@spec-link [[upsilonapi:rule_admin_access_restriction]]` sits on
  `RequireAdmin()`, which only gates *who* may call `/admin/*` routes and
  has no data-shaping logic; this is the wrong code for this atom's actual
  content (see Extra Data).

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | Certain — reproduces on every admin listing/anonymize call that touches a non-anonymized user, deterministic. |
| Impact if triggered | Medium — real PII (home address, birth date) exposed to any admin account beyond the documented "GDPR right to be forgotten" management need; also blocks writing an honest, *green* E2E/CLI test for `rule_admin_access_restriction`'s real content. |
| Detectability | Medium — no automated coverage currently catches it; a naive admin-panel smoke test would look identical whether the fields are censored or not unless it specifically checks the values. |
| Current mitigant | None. |

---

## Recommended Fix

**Short term:** Give `newUserJSON` (or a new `newAdminUserJSON`) an
admin-context variant that nils out/omits `FullAddress`/`BirthDate` for the
`admin.go:users()` and `anonymize()` response paths, matching the atom's
"censor or omit" wording. Move `@spec-link [[upsilonapi:rule_admin_access_restriction]]`
off `RequireAdmin()` (which should instead cite whatever atom governs
admin-route authorization, currently undocumented — see Extra Data) onto the
new censoring code.

**Medium term:** Add Go unit coverage (`admin_users_test.go` already has the
fixture scaffolding) asserting the admin listing omits/nulls these two
fields for a non-anonymized target, alongside the existing
`TestNonAdminCannotReachAdminRoutes`.

**Long term:** Once fixed, `edge_admin_private_data_access.js` can assert
this directly end-to-end via `upsilon.adminSection()` (reachable, unlike the
non-admin-rejection edge blocked by ISS-112) and turn green.

---

## Extra Data

- Companion ATD-doc/mismatch found in the same investigation (ISS-107 audit,
  EC-49): `rule_admin_access_restriction`'s only code-side spec-link
  (`middleware/auth.go:90`, `RequireAdmin()`) enforces route-level
  authorization ("is the caller an admin at all"), not field-level
  censorship ("what may an admin see"). No atom currently documents the
  route-authorization rule itself — flagged as a follow-up doc gap, not
  fixed here per the audit's do-not-touch-shared-atoms-without-flagging
  convention.
- `atd trace upsilonapi:rule_admin_access_restriction` confirms zero
  implementing code for the atom's actual censorship logic despite showing
  `implementation_rate: 0.33` (that rate is driven entirely by the
  mismatched `RequireAdmin()` link).
- Not the same root cause as ISS-112 (CLI harness blocks non-admin callers
  from reaching any `admin_`-prefixed route at all — a harness/routing
  limitation) nor ISS-103 (foe-loadout masking in battle board state,
  `masking.go`, unrelated component/atom). All three are independent,
  unimplemented-privacy-contract bugs in different subsystems; do not
  conflate.
- Discovered while auditing `edge_admin_private_data_access.js` under
  ISS-107; the scenario's own tail (checking the *owner* can see their own
  `full_address`/`birth_date`) already exercised the correct atom by
  accident but the wrong direction (self-visibility, not admin-censorship)
  and asserted nothing about admin views.

---

## References

- `upsilonhub/internal/gateway/resources.go:18-73`
- `upsilonhub/internal/gateway/admin.go:44-58,90`
- `upsilonhub/internal/gateway/middleware/auth.go:86-101`
- `upsilonhub/internal/gateway/admin_users_test.go` (fixture reusable for the recommended unit test)
- `upsiloncli/tests/scenarios/edge_admin_private_data_access.js`
- ISS-112 (admin negative-path CLI harness gap — distinct root cause)
- ISS-103 (foe-loadout masking gap — distinct component, same bug class)
