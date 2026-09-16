# Issue: Hub never retargets DATABASE_URL to the "upsilon" database deploy/initdb provisions for it

**ID:** `20260916_hub_database_url_mismatch`
**Ref:** `ISS-161`
**Date:** 2026-09-16
**Severity:** Medium
**Status:** Resolved
**Component:** `scripts/start_services.sh`
**Affects:** `deploy/initdb/create_databases.sql`, `upsilonhub` (schema/runtime data location), `scripts/check_services.sh`, `.claude/skills/dev-env/SKILL.md`

---

## Summary

`deploy/initdb/create_databases.sql` provisions three per-service databases
on the shared dev Postgres instance — `upsilon`, `upsilonauth`,
`upsiloneconomy` — with a header comment mapping `upsilon` to the hub. In
`scripts/start_services.sh`, the economy and auth process launches *do* get
their `DATABASE_URL` rewritten to their own dedicated database (via a `sed`
swap building `ECONOMY_DB_URL`/`AUTH_DB_URL`), but the hub launch line never
gets the same treatment — it just inherits the devcontainer's raw
`DATABASE_URL`, whose path segment is `postgres` (the Postgres server's own
default administrative database), not `upsilon`. In this dev topology the
hub's entire schema and runtime data have therefore always lived in the
shared `postgres` database; the dedicated `upsilon` database created for it
sits empty and unused.

Discovered while deepening `scripts/check_services.sh` to validate database
schema presence per service (2026-09-16) — the new check initially hardcoded
`upsilon` as the hub's database name (matching the initdb comment and the
`dev-env` skill doc's wording) and reported a false "never migrated" failure
even right after a successful `-migrate-mode full` run, because the
migration was actually landing in `postgres`, not `upsilon`.

---

## Technical Description

### Background

Each of the three Go services (`upsilonhub`, `upsilonauth`, `upsiloneconomy`)
owns its own `golang-migrate`-backed schema, applied via `<binary> -migrate`
(or `-migrate-mode full` for the hub) against whatever database
`DATABASE_URL` points to. The intended dev-topology design (per
`deploy/initdb/create_databases.sql`'s own header comment) is one database
per service, all on the same shared Postgres instance/volume.

### The Problem Scenario

```
docker-compose.yaml (app service env):
  DATABASE_URL=postgres://postgres:postgres@db:5432/postgres
                                                      ^^^^^^^^
                                          Postgres's own default db,
                                          NOT a per-service one.

scripts/start_services.sh:

  ECONOMY_DB_URL="$(printf '%s' "$DATABASE_URL" | sed -E 's#(://[^/]+/)[^/?]+#\1upsiloneconomy#')"
  AUTH_DB_URL="$(printf '%s' "$DATABASE_URL" | sed -E 's#(://[^/]+/)[^/?]+#\1upsilonauth#')"
  # ... economy started with DATABASE_URL=$ECONOMY_DB_URL   -> db "upsiloneconomy"  (correct)
  # ... auth     started with DATABASE_URL=$AUTH_DB_URL     -> db "upsilonauth"      (correct)

  # Hub: NO equivalent HUB_DB_URL / sed rewrite exists.
  start_service "Upsilon Hub" "upsilonhub" \
    "env APP_DEBUG=true ... ./bin/upsilonhub" "hub.log" 8090
  #                                            ^^^^^^^^^^^^^^^^^^^^^^^
  #                          inherits raw DATABASE_URL as-is -> db "postgres"

Result: hub schema/data live in "postgres", not "upsilon".
        "upsilon" database exists (created by create_databases.sql) but is
        always empty in this dev topology.
```

Verified empirically on 2026-09-16 inside the `app` container:

```
$ psql "postgres://postgres:postgres@db:5432/upsilon?sslmode=disable" -tAc '\dt'
Did not find any relations.

$ psql "postgres://postgres:postgres@db:5432/postgres?sslmode=disable" -tAc \
    'select version,dirty from schema_migrations;'
5|f   # the hub's actual, fully-migrated schema
```

### Where This Pattern Exists Today

- `scripts/start_services.sh` — `ECONOMY_DB_URL`/`AUTH_DB_URL` construction
  and their use in the economy/auth `start_service` calls; contrast with the
  "4. Upsilon Hub" block a few lines below, which has no equivalent
  `HUB_DB_URL`.
- `deploy/initdb/create_databases.sql` — header comment states
  `upsilon — upsilonhub (gameplay, characters, matches, player_stats)`,
  which is aspirational, not what actually happens in dev.
- `.claude/skills/dev-env/SKILL.md` — previously documented the hub's
  migrate/seed commands with the comment `(db "upsilon", i.e. the
  container's default DATABASE_URL)`, conflating the two; corrected in the
  same pass that filed this issue (now explicit that the default db is
  `postgres`, and flagged as Gotcha #5).
- CI/prod stacks are unaffected in principle — `HUB_UPSTREAM`/routing aside,
  their `DATABASE_URL` is presumably scoped correctly per environment — but
  this was not verified as part of this investigation; scope was dev-only.

---

## Risk Assessment

| Factor | Value |
|---|---|
| Likelihood | High — happens on every dev-stack start, unconditionally |
| Impact if triggered | Low in isolation (the hub still works — it just uses a differently-named database than intended), but Medium in combination: any manual db-admin command that assumes "upsilon" per the initdb comment (drop/backup/restore/inspect) silently operates on the wrong, empty database while the real data sits in `postgres` |
| Detectability | Low without a schema-aware check — the hub boots and serves traffic normally either way; only visible by inspecting `\dt` per database or diffing `schema_migrations` versions |
| Current mitigant | `scripts/check_services.sh` (this same change) now reads the hub's database name out of its actual `DATABASE_URL` rather than assuming `upsilon`, so a schema check no longer produces a false failure — but this doesn't fix the underlying mismatch, just avoids false-alarming on it |

---

## Recommended Fix

**Short term:** Documented in `.claude/skills/dev-env/SKILL.md` (Gotcha #5)
and accounted for in `scripts/check_services.sh` — both now treat "whatever
`DATABASE_URL` the hub actually inherits" as ground truth instead of
assuming `upsilon`.

**Medium term:** Decide intentionally whether the hub *should* get its own
`HUB_DB_URL` (mirroring `ECONOMY_DB_URL`/`AUTH_DB_URL`) in
`start_services.sh`, retargeting it to the dedicated `upsilon` database like
the other two services — bringing dev in line with the per-service-database
design `create_databases.sql` documents. This is a behavior change (existing
dev volumes would need a one-time data migration or reseed from `postgres`
into `upsilon`) and was deliberately left out of this change pending a
decision from the team.

**Long term:** If the per-service-database split is the intended end state
everywhere, add a startup assertion (or a `check_services.sh` warning) that
fails loudly if a service's `DATABASE_URL` path segment doesn't match its
expected database name, so this class of drift can't happen silently again.

---

## Extra Data

Found while implementing deeper `scripts/check_services.sh` checks (schema
presence/version/dirty-flag per service, HTTP-level `/health`/`/up` probes,
and a front-door routing check through `proxy:8085`), at the user's request
to make service-health checking less shallow than pure PID/port liveness.

---

## References

- `scripts/start_services.sh`
- `scripts/check_services.sh`
- `deploy/initdb/create_databases.sql`
- `.claude/skills/dev-env/SKILL.md` (Architecture recap, Database section, Gotcha #5)

---

## Resolution (2026-09-16)

The actual root cause was narrower than this issue originally framed: fixing
it did **not** require the "Medium term" `HUB_DB_URL`/`sed` rewrite proposed
above for `scripts/start_services.sh`. That script's `ECONOMY_DB_URL`/
`AUTH_DB_URL` derivation is base-URL-agnostic — it rewrites whatever
`DATABASE_URL` it's handed, so it needed no change at all. The real defect
was one line in `docker-compose.yaml`: the `app` service declared
`DATABASE_URL=postgres://postgres:postgres@db:5432/postgres` (the Postgres
maintenance database) instead of the dedicated `upsilon` database
`deploy/initdb` already provisioned. The fix landed at the compose level,
where dev-topology constants belong, not by hand-copying a derivation into
the start script:

- `docker-compose.yaml`: `DATABASE_URL` now reads
  `postgres://postgres:postgres@db:5432/upsilon?sslmode=disable` — matching
  `docker-compose.ci.yaml`'s `upsilon` target, and adding `?sslmode=disable`
  to retire the long-standing "every `-migrate`/`-seed` fails with `pq: SSL
  is not enabled on the server` unless you append it by hand" gotcha (dev was
  the only topology missing it; CI/prod already carried it).
- The `app` container was recreated so the new env took effect, then the hub
  was migrated (`-migrate-mode full`) and seeded (`-seed`) into `upsilon`.
  The old schema/data was left in place in `postgres` (not dropped).
- `scripts/check_services.sh`'s per-service schema check — previously a
  descriptive read of "whatever database the hub's `DATABASE_URL` actually
  names" — is now a genuine assertion (Long term fix from this issue): it
  compares each service's `DATABASE_URL` path segment against its expected
  database name (`upsilon`/`upsilonauth`/`upsiloneconomy`) and fails loudly
  on a mismatch, instead of silently reporting schema health for the wrong
  database.
- `.agent/skills/dev-env/SKILL.md`: Gotcha #5 (hub/`upsilon` mismatch) and
  Gotcha #1 (`?sslmode=disable` workaround) are both marked
  retired/historical; the Architecture recap and Database-section examples
  now reflect the hub using `upsilon` with no manual `DATABASE_URL` override
  needed.

Verified: `docker compose exec -T app bash -lc 'echo $DATABASE_URL'` shows
the `upsilon?sslmode=disable` URL; `schema_migrations` in `upsilon` is at
the highest migration version, not dirty; `./scripts/start_services.sh`
brings up the full stack with no `DATABASE_URL` override on the command
line; `./scripts/check_services.sh` exits 0 including the new assertion;
`e2e_gdpr_portability` passes (`CR-14: GDPR DATA PORTABILITY PASSED`).

## Change Log

- **2026-09-16**: Resolved. Root cause was a single `docker-compose.yaml`
  line, not a missing `start_services.sh` rewrite as originally framed; see
  Resolution above.
