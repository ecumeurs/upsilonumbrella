# Issue: GDPR erasure still leaves purchase history intact — `player_inventory`/`inventory_transactions` need a pseudonymize-vs-erase decision

**ID:** `20260918_gdpr_erasure_inventory_purge_undecided`
**Ref:** `ISS-167`
**Date:** 2026-09-18
**Severity:** Medium
**Status:** Open
**Component:** `upsiloneconomy/internal/economy` (`player_inventory`, `inventory_transactions`), `upsiloneconomy/internal/api/gdpr.go`, `upsilonauth/internal/economypurge`
**Affects:** GDPR Art. 17 erasure completeness; the ISS-165 fix

---

## Summary

ISS-165's fix (worktree `upsilon-hub-iss-165`, reviewed OKAY, not yet merged) makes account
deletion fan out a durable `economy_purge` job that zeroes the wallet and closes the credit
ledger. It deliberately does **not** touch `player_inventory` or `inventory_transactions` —
those tables were out of scope for that fix and remain untouched by any erasure path today.
This issue tracks that residual gap and, more importantly, the decision it's blocked on: **is
the right treatment pseudonymization (keep the row, redact/zero it, like the wallet) or actual
row deletion (erase)?** The two tables don't have symmetric answers, because their schemas
aren't symmetric — see below.

---

## Technical Description

### Background: the precedent `Purge` already set for wallets

`upsiloneconomy/internal/economy/pg_wallet.go:123-164` (`PG.Purge`) is the shape any inventory
purge would extend: never delete the wallet row, insert a closing ledger entry
(`source = "gdpr_purge"`, `amount = -balance`) keyed by an idempotency key, then zero the
balance. That works because `credit_transactions.source` is a free `varchar(255)` with no
`CHECK` constraint (`db/migrations/000001_economy_schema.up.sql:51-63`) — `"gdpr_purge"` is
just another string it already accepts.

### The problem: `inventory_transactions` cannot accept the same pattern as-is

```sql
-- db/migrations/000001_economy_schema.up.sql:73-83
CREATE TABLE inventory_transactions (
    id uuid NOT NULL,
    player_id uuid NOT NULL,
    shop_item_id uuid NOT NULL,
    quantity integer NOT NULL,
    credits_spent integer NOT NULL,
    transaction_type character varying(16) DEFAULT 'purchase' NOT NULL,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    CONSTRAINT inventory_transactions_type_check CHECK (
        (transaction_type)::text = ANY (ARRAY['purchase','refund','gift','admin_grant']::text[])
    )
);
```

Unlike `credit_transactions.source`, `transaction_type` is **closed** by a `CHECK` constraint
with four values, none of which is a purge/closure marker. A wallet-style "insert a closing row
with source `gdpr_purge`" needs either a migration to widen the enum, or a different mechanism
entirely (e.g. a boolean/timestamp `purged_at` column instead of a synthetic transaction row).

`player_inventory` (`db/migrations/000001_economy_schema.up.sql:27-41`) has no transaction-type
concept at all — it's a materialized "what does this player currently hold"
(`player_id, shop_item_id, quantity`) with a `UNIQUE (player_id, shop_item_id)` constraint. There
is no analogue of "zero the balance" that preserves referential/audit value the way the wallet
row does; zeroing `quantity` to 0 changes its meaning to "player currently holds none", which is
observably different from "player was erased."

### Why this is a decision, not just an implementation task

1. **If `inventory_transactions` is legally similar to `credit_transactions`** (financial/audit
   record — what was bought, when, for how much), the correct move is likely the same
   pseudonymization pattern: retain the rows (needed for economy reconciliation, shop analytics,
   fraud/chargeback history), but the schema needs a migration first (widen the `CHECK`, or add a
   purge marker column) before any closing-row or redaction approach can be implemented.
2. **If `player_inventory` is treated as active account state rather than an audit trail**, hard
   deletion on erasure is defensible — a deleted account holding items server-side has no
   ongoing product purpose, unlike a financial ledger. But this needs to be stated explicitly,
   since it would be the *only* hard-delete path in the erasure design ISS-165 established
   (everything else is zero-and-close, never delete).
3. Whichever way this goes, `upsiloneconomy/internal/api/gdpr.go:30-42` (the purge route) and the
   `PG.Purge` method need a matching extension, and `upsilonauth/internal/economypurge` (ISS-165)
   needs to call it — the durable job/queue plumbing ISS-165 built already covers "call economy's
   purge endpoint once on erasure," so wiring a second call (or extending the existing DTO) is the
   easy part once the schema/policy question is settled.

### Where this was flagged before

- `issues/ISS-165_20260917_gdpr_erasure_never_reaches_economy.md`, Recommended Fix item 4 (not
  yet acted on).
- `architecture/account_lifecycle.md` §7.4 ("What this fix does not close").

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | Certain — no code path purges or pseudonymizes either table today, even after ISS-165 merges |
| Impact if triggered | Medium — retained personal data (purchase history tied to a UUID) after a lawful erasure request, same legal exposure class as ISS-165 but narrower (no live financial balance at stake) |
| Detectability | Very low — same silent-success shape as ISS-165: erasure "succeeds" with no error, no log line |
| Current mitigant | None. `PG.Purge` (wallet) sets precedent for the *pattern* but does not cover these tables |

---

## Recommended Fix

**Short term:** Get an explicit decision (product/legal, not engineering) on treatment per
table:
- `inventory_transactions`: pseudonymize-in-place (retain rows, close out) vs. hard delete.
- `player_inventory`: hard delete vs. zero-and-retain.

Document the decision and its rationale in `architecture/account_lifecycle.md` §7.4 before any
code changes, since it sets a second precedent (financial ledgers pseudonymize; does everything
else follow suit, or is there a principled split between "active state" and "historical record"
tables?).

**Medium term:** Once decided —
- If `inventory_transactions` pseudonymizes: migration to widen `transaction_type`'s `CHECK`
  constraint (or add a dedicated `purged_at`/`redacted` column instead of overloading
  `transaction_type`), then extend `PG.Purge` (or add a sibling method) to close it out
  idempotently, matching the wallet pattern.
- If `player_inventory` hard-deletes: extend `PG.Purge` to `DELETE FROM player_inventory WHERE
  player_id = $1` inside the same transaction as the wallet closure, so it stays atomic and
  idempotent (a second delete of already-gone rows is a no-op).
- Extend `upsilonauth/internal/economypurge`'s existing `economy_purge` job/DTO to carry
  whatever the extended `Purge` call needs — no new queue or job kind required, this rides the
  ISS-165 plumbing.

**Long term:** Fold this into the same `how_to_add_a_service.md` §7 requirement ISS-165 amended
(export fragment + purge path per service) — make explicit that "purge path" means a *documented
per-table* treatment, not just an endpoint that exists, since this issue shows a single service
can have tables needing opposite treatments.

---

## Extra Data

Schema facts (table definitions, constraints) verified directly against
`upsiloneconomy/db/migrations/000001_economy_schema.up.sql` on 2026-09-18. No code changes made
by this issue — investigation only, per instruction to leave the policy call to a human.

Per the current ATD tooling pause (see project memory), no atom updates or `atd` commands were
run as part of filing this issue.

---

## References

- `upsiloneconomy/internal/economy/pg_wallet.go` (`Purge`, the pattern this issue asks to extend or deliberately not extend)
- `upsiloneconomy/internal/api/gdpr.go` (purge route)
- `upsiloneconomy/db/migrations/000001_economy_schema.up.sql:27-41,51-63,73-88` (schemas compared)
- `upsilonauth/internal/economypurge/` (ISS-165's fan-out, worktree `upsilon-hub-iss-165`)
- `issues/ISS-165_20260917_gdpr_erasure_never_reaches_economy.md`
- `architecture/account_lifecycle.md` §7.4
