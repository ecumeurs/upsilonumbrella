# Issue: GDPR account deletion never reaches economy — credits, ledgers and inventory survive erasure

**ID:** `20260917_gdpr_erasure_never_reaches_economy`
**Ref:** `ISS-165`
**Date:** 2026-09-17
**Severity:** High
**Status:** Resolved
**Component:** `upsilonauth/internal/identity` + `upsilonauth/internal/accountpush` (fan-out), `upsiloneconomy/internal/api` (orphaned purge endpoint)
**Affects:** Every account that exercises its right to erasure; GDPR Art. 17 compliance

---

## Summary

`upsiloneconomy` implements a correct, idempotent GDPR purge — `PG.Purge` zeroes the wallet
and writes a closing `gdpr_purge` ledger row — and exposes it over its internal API. **Nothing
in the platform ever calls it.** Account deletion in `upsilonauth` anonymizes and soft-deletes
the auth row and fans out a single `account_push` job to the hub, which only mirrors
`deleted_at` into its `playerstats` read model. Economy is never told. A deleted account's
wallet balance, credit ledger, inventory and inventory ledger remain intact and attributable
to its UUID indefinitely.

This is the exact mirror of ISS-118: that issue found the **portability** right incomplete
after the service extraction; this is the **erasure** right, broken by the same seam.

---

## Technical Description

### The dead endpoint

`upsiloneconomy/internal/economy/pg_wallet.go:118-163` — `Purge(ctx, userID, idempotencyKey)`
lazy-creates the wallet, takes a row lock, inserts an idempotency-keyed
`source = "gdpr_purge"` transaction for `-balance`, then sets the balance to `0`. It is
exposed at `upsiloneconomy/internal/api/gdpr.go:30-42`. The implementation is sound and
tested.

### The missing caller

```
grep -rn "gdpr_purge\|EconomyPurge\|PurgeAccount" --include=*.go upsilonhub upsilonauth upsiloneconomy
```
returns only the two lines *inside* `upsiloneconomy/internal/economy/pg_wallet.go` that define
it. There is no caller in any other service.

Tracing the actual deletion path confirms it:

1. `upsilonauth/internal/gateway/auth.go:192` `deleteAccount` → `identity.DeleteAndAnonymize`.
2. `upsilonauth/internal/accountpush/producing.go:87` wraps it: run the local mutation, then
   `pushByID` → one `account_push` River job.
3. That job carries only `UserID`, `AccountName`, `DeletedAt`, `UpdatedAt`
   (`producing.go:108-115`) and is consumed at
   `upsilonhub/internal/gateway/internal_consumer.go:112`, which calls
   `playerstats.UpsertAccount` and nothing else.
4. `upsilonhub/internal/transport/economyclient/client.go` has exactly three methods —
   `GetWallet`, `ListWallets`, `AwardCreditsIdempotent`. **No purge method exists on the
   client at all**, so even the hub could not forward an erasure if it wanted to.

### Live confirmation

The dev stack holds 13 anonymized, soft-deleted `gdpr_bot_*` accounts (deleted
2026-09-16 15:07–15:57). `Purge` lazy-creates a wallet row before zeroing it, so a purge that
ran would leave one `wallets` row and one `gdpr_purge` `credit_transactions` row per deleted
account. Actual state of `upsiloneconomy`:

```
select count(*) from wallets;              ->  0
select count(*) from credit_transactions;  ->  0
select count(*) from shop_items;           ->  8   (seeded — the DB is provisioned, not blank)
```

Zero purge effects against 13 deletions. The fan-out demonstrably never fired.

### Why nobody noticed

Those particular bots never touched economy, so they had no wallet to erase and the omission
left no visible residue. The defect is silent by construction: it only produces retained
personal data for accounts that actually earned, spent or held credits — and it produces no
error, no log line, and no failing test in any case.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | Certain — no code path can invoke the purge |
| Impact if triggered | High — retained financial personal data after a lawful erasure request (GDPR Art. 17) |
| Detectability | Very low — succeeds silently; economy is never consulted, so nothing can fail |
| Current mitigant | None. Pre-launch dev data only, and the accounts erased so far happened to hold no wallet |

---

## Recommended Fix

Extend the existing durable fan-out rather than inventing a new mechanism — `AccountPush` is
already the right shape (River job, at-least-once, idempotency key available).

1. Add `PurgeAccount(ctx, userID, idempotencyKey)` to `upsilonhub`'s `economyclient` **or**
   give auth a direct economy seam. Prefer the latter: erasure is auth's responsibility as
   GDPR authority, and routing it through the hub makes a game module a dependency of a
   platform-wide legal obligation.
2. On `DeleteAndAnonymize`, enqueue a durable economy-purge job alongside the existing
   account push. Use the account UUID + a deletion-scoped idempotency key so replays are
   safe — economy's `InsertCreditTransactionIdempotent` already enforces this and returns
   `rows == 0` on replay.
3. **Fail loudly, not closed-and-quiet.** Unlike the export, erasure cannot be synchronously
   refused — the user's account is already gone. The job must retry durably and surface to
   an operator if it exhausts retries; a silently dropped purge is the current bug.
4. Apply the same treatment to any future service holding personal data. §7 of
   `architecture/how_to_add_a_service.md` and the `add-a-service` skill now require both an
   export fragment *and* a purge path — this issue is why the purge half is named there.
5. Add an E2E scenario that deletes an account holding a non-zero balance and asserts the
   economy-side effect, so the erasure right gets the same end-to-end proof ISS-118 gave the
   portability right.

---

## Extra Data

Found on 2026-09-17 while investigating an unrelated `"wallet": null` question during ISS-118
close-out. The wallet question itself resolved benignly (wallets are lazily created; `null` is
faithful), but the supporting database evidence — zero wallet rows across 13 purged accounts —
exposed this.

Note for the record: `issues/Ref_20260722_gdpr_export_per_game_gap.md` (ISS-118) asserted that
"Deletion/anonymization is already handled durably (auth River fan-out → economy purge);
export is the only right that regressed." That statement is **false** and has been corrected
in that file. The erasure fan-out to economy was never built.

---

## References

- `upsiloneconomy/internal/economy/pg_wallet.go` (`Purge`, orphaned)
- `upsiloneconomy/internal/api/gdpr.go` (purge route, unreachable in practice)
- `upsilonauth/internal/accountpush/producing.go` (the fan-out that omits economy)
- `upsilonhub/internal/gateway/internal_consumer.go:112` (hub consumer, playerstats only)
- `issues/Ref_20260722_gdpr_export_per_game_gap.md` (ISS-118 — the portability mirror of this)
- `upsiloneconomy:mechanic_gdpr_purge` (atom describing the behaviour nothing triggers)
