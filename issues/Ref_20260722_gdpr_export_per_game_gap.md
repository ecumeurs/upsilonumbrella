# Issue: GDPR export loses per-game data coverage under the game-agnostic account model

**ID:** `20260722_gdpr_export_per_game_gap`
**Ref:** `ISS-118`
**Date:** 2026-07-22
**Severity:** Medium
**Status:** Resolved
**Component:** `upsilonauth/internal/gateway` (export), `upsilonhub/internal/gateway` (game data)
**Affects:** GDPR `GET /api/v1/auth/export` consumers; every future game service

---

## Summary

Under the 2026-07-22 remodel, upsilonauth's `GET /auth/export` returns account data + registered services only — it no longer aggregates characters/game data (the hub's Laravel-era export bundled the roster). GDPR data-portability, however, covers **all** personal data, including game-local state (characters, match history, inventory, ledgers). Until each game exposes its own export and something composes them, the platform's export answer is incomplete.

---

## Technical Description

### Background

Pre-extraction, one process owned all tables, so one export query covered everything. Post-extraction, personal data is deliberately spread: auth (account), economy (wallet + ledgers), each game (characters, stats, history).

### The Problem Scenario

1. Player invokes their GDPR export right via `GET /api/v1/auth/export`.
2. Auth returns account + registrations (+ tokens metadata).
3. Characters, match history, inventory and credit ledgers exist in hub/economy databases but are absent from the response.
4. The platform has technically under-delivered on data portability.

### Where This Pattern Exists Today

- `upsilonauth/internal/gateway` export handler (returns `characters: []` placeholder as of the Phase-1 scaffold).
- Hub still owns the full data until Phase 4/5 cutover — so today the *hub's* export path is authoritative; the gap opens at cutover.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | High — every export request after cutover is incomplete |
| Impact if triggered | Medium — compliance/user-trust, no availability impact |
| Detectability | Low — the response succeeds, just with less data |
| Current mitigant | Cutover not done yet; deletion path is unaffected (auth's durable purge fan-out zeroes wallets and anonymizes the account) |

---

## Recommended Fix

**Short term:** Before the Phase-4 cutover, document the reduced export scope in the export response itself (a `scope` field listing what is included) so it is honest, and keep this issue open as the cutover gate's known exception.

**Medium term:** Each service exposes an internal export fragment (`GET /internal/v1/gdpr/export/{user_id}` on economy and on each game); auth's export composes the fragments of the services the account is registered to (it already knows the registration list).

**Long term:** Make the export fragment part of the "how to add a service" checklist — a service that stores personal data MUST ship its fragment endpoint before going live (add to `architecture/how_to_add_a_service.md` §7/§0 gates).

---

## Extra Data

Born from the 2026-07-22 game-agnostic accounts remodel (auth = account+registrations only; games own their data).

> **Correction (2026-09-17).** This section originally claimed "Deletion/anonymization is already handled durably (auth River fan-out → economy purge); export is the only right that regressed." **That was false.** Economy implements an idempotent purge and exposes it internally, but nothing in the platform ever calls it — auth's delete path fans out a single `account_push` job to the hub, which only mirrors `deleted_at` into `playerstats`. Verified live: 13 anonymized/soft-deleted accounts, zero corresponding wallet or `gdpr_purge` ledger rows in economy. The erasure right has the same seam-shaped hole this issue found in the portability right; filed as **ISS-165**.

---

## References

- `upsilonauth/docs/contract_auth_service.atom.md` (GDPR clause)
- `architecture/how_to_add_a_service.md`
- `issues/Ref_20260722_upsilonapi_dependabot_vulns.md` (same session's security pass)

---

## Resolution (2026-09-17)

**Resolved.** `GET /api/v1/auth/export` now returns a genuinely complete, composed export.

**Shape shipped.** upsilonauth stays the GDPR authority and sole public route owner; it reads
no other service's database. It composes three fragments synchronously, in stable order —
auth-local identity, economy, then the game fragments the account is registered to — each over
the existing internal-token S2S seam with typed, versioned DTOs in `upsilontypes`
(`authv1`/`economyv1`/`battlev1`, each carrying a `schema_version`).

**Fail-closed, as the issue demanded.** `selectGDPRCollector` returns the real
`HTTPGDPRFragmentCollector` only when both `HUB_INTERNAL_URL` and `ECONOMY_INTERNAL_URL` are
configured; otherwise it returns `UnavailableGDPRFragmentCollector` and the endpoint answers
`503 export_incomplete`. A `200` is therefore a hard completeness claim — the short-term
"document the reduced scope honestly" mitigation was not needed, because the reduced scope no
longer exists. An empty owned dataset is a successful empty fragment; an absent one fails the
aggregate.

**Privacy.** The internal account UUID scopes the internal queries but never appears in the
public payload, preserving `requirement_customer_user_id_privacy`. An unregistered account
omits the `tactical` key entirely rather than emitting a zero-valued placeholder in a legally
significant document.

**Long-term recommendation also done.** §0 and §7 of `architecture/how_to_add_a_service.md`
and the `add-a-service` skill now make the export fragment *and* the purge path a go-live gate
for any service storing personal data, including the empty-vs-absent rule and the
lazy-creation caveat (a row created on read must not be created by the export).

**Verification.** The `e2e_gdpr_portability` scenario passes live against the full stack —
`200`, `complete: true`, all three fragments, no password/token/internal UUID in the payload.
Unit and contract suites green across upsilonauth, upsiloneconomy, upsilonhub and upsilontypes
(including a byte-exact JSON contract test); code health zero-error on every file this work
authored. An independent reviewer returned OKAY on the full diff.

**Two findings this work surfaced, deliberately not fixed here:**

- **ISS-165** — the *erasure* right never reaches economy (see the Extra Data correction
  above). Out of scope: it is durable-fan-out work, not export work.
- A live export legitimately returns `"wallet": null` for an account that has never touched
  economy. Investigated and confirmed correct, not a gap: wallets are lazily created at
  `DefaultWalletBalance = 1000` on first read/award/purchase, and the export uses a dedicated
  query that must never lazy-create. Rendering `{"balance": 0}` instead would be an
  affirmative false claim, since the balance materializes at 1000 the moment anyone reads it.
