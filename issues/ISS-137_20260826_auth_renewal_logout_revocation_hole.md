# Issue: Logout during the sliding-renewal window can leave a freshly-minted replacement token live if the client ignores the surfaced renewal

**ID:** `20260826_auth_renewal_logout_revocation_hole`
**Ref:** `ISS-137`
**Date:** 2026-08-26
**Severity:** Medium
**Status:** Resolved
**Component:** `upsilonauth/internal/gateway/auth.go` (logout call site) / `upsilonauth/internal/identity/pg.go` (`RevokeToken`, `RenewToken`) / `upsilonauth/internal/identity/identity.go` (sliding-renewal window)
**Affects:** any client that receives a renewed token via `meta.token`/`renewed_token` but logs out with the token id it originally held instead of adopting the replacement

---

## Summary

A latent revocation hole was found while investigating ISS-130 (it is **not** the cause of ISS-130
and was never triggered by it — ISS-130's scenario never got far enough to exercise renewal at
all; this is filed purely on its own merit). Introspection performs sliding renewal: when a
token's age falls inside the 10–15 minute window, the identity layer mints a replacement and
truncates the OLD token's expiry to a 20-second grace window. The replacement **is** surfaced to
the caller on the very same response (`resp.RenewedToken` in `introspect.go`, and
`respond.RenewedTokenKey` → `meta.token`/`meta.message` via the `TokenRenewal` middleware on every
other authenticated endpoint) — this issue's original write-up asserted otherwise and was wrong;
see "2026-09-19 correction" below. The residual gap is narrower: `RevokeToken` at logout time
deletes only the single token row whose id is presented. A client that never wires the renewal
signal back into its session state — i.e. it keeps using the old id it already had in hand instead
of adopting `meta.token` — and then logs out while that old id still authenticates (inside its
20-second grace window) leaves the true current (renewed) token untouched and live until natural
expiry.

---

## Technical Description

### Background

Introspection and the `TokenRenewal` middleware share one renewal decision
(`middleware.ShouldRenew`): a token aged 10–15 minutes gets a replacement minted with a fresh
15-minute TTL, and the superseded row is not deleted immediately — it is put on a 20-second grace
window (`RenewToken` in `upsilonauth/internal/identity/pg.go`) so a request already in flight with
the old token still authenticates. Logout is expected to end the session for good by revoking the
caller's current token.

### The Problem Scenario

```
CLI / client                 upsilonauth
─────────────                ───────────
request N  (token=T_old, age=12m, inside 10-15m renewal window)
                              introspect(T_old) -> valid
                              renewal fires -> mints T_new
                              T_old truncated to a 20s grace window (not "still valid
                              indefinitely" — it dies on its own shortly after)
  response carries T_new: introspect's resp.renewed_token, or meta.token on every
  other authenticated response (TokenRenewal middleware) -- T_new IS surfaced here
IF the client does not adopt T_new into its session (a bug/gap in that client, not
in auth) and instead logs out with the id it already held:

logout(T_old id) ────────────► RevokeToken deletes ONLY T_old's row
                              T_new row is untouched, still valid, still usable
request N+1 (token=T_new) ──► introspect(T_new) -> still valid, 200 OK
                              (expected: 401, session was supposed to be over)
```

`RevokeToken` (`upsilonauth/internal/gateway/auth.go`'s logout call site, implemented in
`upsilonauth/internal/identity/pg.go`) deleted exactly the one token ID it was handed; it had no
notion of a token lineage/family, so a renewal-spawned sibling was invisible to it. **This has now
been fixed — see Resolution below.**

### Why It Was Latent, Not Active Today

Renewal only fires when token age is between 10 and 15 minutes
(`upsilonauth/internal/identity/identity.go:31-35`, the `RenewAfter`/`TokenTTL` constants). Any
scenario or real session shorter than that window never reaches the renew-then-revoke
interleaving. Additionally — and this is the part the original write-up got wrong — even inside
that window, no current client actually drops the renewal on the floor: both `upsiloncli`
(`internal/api/client.go` → `session.HandleTokenRenewal(meta)`) and `upsilonbattleui`
(`src/services/auth.js`) centrally auto-adopt `meta.token`/`renewed_token` on every response, so
neither ever logs out holding a stale id while a live successor exists. The hole was real at the
data-layer/API-contract level (nothing enforced the invariant) but had no live exploitable path
through either shipped client.

### Note: The Baseline Revocation Chain Is Sound

This was never a report that revocation is broken in general. The normal chain was verified
correct end to end during the ISS-130 investigation: `logout` → `RevokeToken` → deletion of the
token row → `FindTokenByID`/`FindTokenByHash` → `pgx.ErrNoRows` → `ErrUnauthenticated` →
`{active:false}` → 401, pinned by `TestIntrospectRevokedToken`
(`upsilonauth/internal/gateway/introspect_test.go:86-99`). The gap was specifically the
renew-then-revoke interleaving — revoking a token whose lineage had already forked — not
revocation itself.

---

## 2026-09-19 correction (of the original 2026-08-26 write-up)

The original Problem Scenario diagram and References section contained three factual errors,
corrected here rather than silently rewritten so the investigation trail stays honest:

1. **"T_old still stored too / still valid, still usable" was false.** `RenewToken` truncates
   T_old's `expires_at` to `now + GraceTTL` (20 seconds) in the same call that mints T_new. T_old
   is not a second permanently-live token; it is a short-lived remnant that expires on its own
   shortly after renewal, independent of any logout.
2. **"`middleware.AuthToken` returns T_old and T_new is not surfaced" was false.** The replacement
   plaintext IS surfaced on the same response that triggered renewal: `resp.RenewedToken` in
   `introspect.go`, and `respond.RenewedTokenKey` → `meta.token` (plus `meta.message`) via the
   `TokenRenewal` middleware on every other authenticated endpoint. `middleware.AuthToken` returning
   the old token's *metadata* for the current request's own authorization is correct and unrelated
   to whether the client is told about the successor — it is told, via `meta`, not via `AuthToken`.
3. **The `upsiloncli/internal/script/bridge.go:168` citation was mischaracterized.** That line is
   `endpoint.SyncSession(resp, a.Session)`, the login/register `data.token` capture path — unrelated
   to sliding renewal. The actual renewal-sync path is `upsiloncli/internal/api/client.go` →
   `session.HandleTokenRenewal(meta)`, with the SPA equivalent at
   `upsilonbattleui/src/services/auth.js`. Both auto-adopt the renewed token centrally, which is why
   this was never observed live (see "Why It Was Latent" above).

Stale line references from the original write-up, corrected: `auth.go:151-155` (the logout call
site plus the real `RevokeToken`/`RenewToken` implementations now live in `identity/pg.go`, not at
those line numbers); `identity.go:31-33` → `:31-35`; `pg.go:253-255` (`DeleteToken`) is now
generated sqlc code under `internal/identity/identitypg/` and no longer hand-written at that
location; `introspect_test.go:83-99` → `:86-99`.

The real residual, restated narrowly: logout revoked only the presented token's row, so a client
that ignores `meta.token`/`renewed_token` entirely and logs out with an already-superseded
grace-window token would have left the true current token live. No current client (CLI, SPA)
behaves that way — both auto-adopt centrally — but nothing in the data model or the logout
contract enforced the invariant, which is what made this worth closing regardless.

---

## Resolution

Fixed via a `family_id` (uuid) lineage column on `personal_access_tokens`
(`upsilonauth/db/migrations/000003_token_family.up.sql`):

- `IssueToken` assigns a **fresh** `family_id` on every root token (login/register/admin-login) —
  concurrent logins for the same user never share a family.
- `RenewToken`'s successor **inherits** the predecessor's `family_id` verbatim — renewal extends a
  lineage, it never starts a new one.
- `RevokeToken` now deletes every row sharing the presented token's `family_id` in one statement
  (`DeleteTokenFamily`, `internal/identity/queries.sql`), so logout with EITHER a predecessor's or
  a successor's id kills the whole chain.
- Pre-existing rows (migration backfill) each get their own fresh, single-member `family_id`: they
  predate lineage tracking, so treating them as already-independent sessions is the only backfill
  that does not silently merge unrelated logins into one revocable family or leave rows orphaned
  with a null `family_id`.

Covered by `TestIntrospectRevokeCascadesToRenewedFamily`
(`upsilonauth/internal/gateway/introspect_test.go`), which pins both directions: revoking the old
id kills the renewed successor, and revoking the new id kills the original. Written and confirmed
failing against the pre-fix single-row `DeleteToken` behavior before the cascade was implemented,
per the test-first-on-bugs rule.

Atoms: new `upsilonauth:mech_token_revocation_cascade` (the cascade logic), amended
`upsilonauth:mech_sanctum_token_renewal` v2.1 (family inheritance on renewal), amended
`upsilonapi:api_auth_logout` v1.1 (whole-family revocation is now the logout contract).

This issue was kept Open rather than retired at first fix, pending verification against a real
database — see the 2026-09-20 Change Log entry below for that verification and the resulting
closure.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | Was low even pre-fix — required a request to land inside the narrow 10-15 minute renewal window immediately before logout with a client that ignores the surfaced renewal signal; no observed occurrence in CI, and no shipped client behaves that way |
| Impact if triggered | Medium — a token the user believes is revoked would remain usable until natural expiry |
| Detectability | Low pre-fix — introspection on the replacement token returned a normal 200; nothing distinguished it from a legitimately still-valid session |
| Current mitigant | `RevokeToken` now cascades by `family_id` (see Resolution) |

---

## Change Log

- **2026-08-26**: Filed. Recommended short/medium/long-term mitigations (document as known gap;
  revoke whole lineage on logout or make renewal discoverable to revoke; consider mutate-in-place
  renewal as a longer-term direction).
- **2026-09-19**: Corrected three factual errors in the original write-up (T_old grace-window
  truncation misdescribed as "still valid"; T_new claimed not surfaced when it is, via
  `meta.token`/`renewed_token`; `bridge.go:168` citation mischaracterized — real renewal sync is
  `upsiloncli/internal/api/client.go`/`upsilonbattleui/src/services/auth.js`). Implemented the
  `family_id` lineage cascade (migration `000003_token_family`, `IssueToken`/`RenewToken`/
  `RevokeToken` changes in `upsilonauth/internal/identity/pg.go`), added
  `TestIntrospectRevokeCascadesToRenewedFamily` (written and confirmed failing against the pre-fix
  behavior first). Added atom `upsilonauth:mech_token_revocation_cascade`; amended
  `upsilonauth:mech_sanctum_token_renewal` (v2.1) and `upsilonapi:api_auth_logout` (v1.1). Kept
  Status **Open** per maintainer direction pending soak/atom promotion, not retired.
- **2026-09-20**: Verified against a real, non-testcontainer dev Postgres, not just unit tests.
  Migration `000003_token_family` applied cleanly (`schema_migrations` at v3; `family_id` column
  NOT NULL with its btree index; the two pre-existing rows backfilled with distinct uuids, not a
  shared one). `go test -p 1 ./internal/identity/... ./internal/gateway/...` passed in full,
  including both subtests of `TestIntrospectRevokeCascadesToRenewedFamily`. Exercised the actual
  live flow through the running auth service behind Caddy: logged in, forced the request inside
  the real 10-15 minute renewal window, confirmed `meta.message: "Token renewed"` and a fresh
  `meta.token` on the response, then logged out using the OLD (pre-renewal, still-in-grace-window)
  token id — a direct query afterward showed both the old and the new token rows deleted, i.e. the
  exact scenario this issue described no longer leaves a live replacement. Down-migration
  reversibility also confirmed (drops `family_id`+index cleanly; re-up restores both without
  touching pre-existing row data). No bugs found in the committed fix. Commit `c764579`
  (`upsilonauth`). Status set to **Resolved**.

---

## References

- `upsilonauth/internal/gateway/auth.go` — `logout` handler (call site of `RevokeToken`).
- `upsilonauth/internal/identity/pg.go` — `RevokeToken`, `RenewToken`, `IssueToken` (the fix).
- `upsilonauth/internal/identity/identity.go:31-35` — renewal window constants.
- `upsilonauth/internal/gateway/introspect.go` — `resp.RenewedToken` surfacing.
- `upsilonauth/internal/gateway/middleware/auth.go` — `TokenRenewal` middleware,
  `respond.RenewedTokenKey` → `meta.token`.
- `upsilonauth/internal/gateway/introspect_test.go:86-99` — `TestIntrospectRevokedToken`, pins the
  sound baseline chain; `TestIntrospectRevokeCascadesToRenewedFamily` — pins the fix.
- `upsilonauth/db/migrations/000003_token_family.up.sql` / `.down.sql` — the `family_id` schema
  change.
- `upsiloncli/internal/api/client.go` → `session.HandleTokenRenewal(meta)` — CLI-side renewal sync
  (not `bridge.go:168`, which is the unrelated login/register `SyncSession` path).
- `upsilonbattleui/src/services/auth.js` — SPA-side renewal sync equivalent.
- Related: ISS-130 (resolved; file removed 2026-08-27) — found while investigating that report;
  unrelated cause, this hole was never triggered by it.
