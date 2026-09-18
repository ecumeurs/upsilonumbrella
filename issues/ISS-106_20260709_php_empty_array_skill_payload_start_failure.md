# Issue: Stored skill payloads with PHP-era `[]` empty objects break arena start; join still reports "matched"

**ID:** `20260709_php_empty_array_skill_payload_start_failure`
**Ref:** `ISS-106`
**Date:** 2026-07-09
**Severity:** Low
**Status:** Resolved
**Component:** `upsilonapi/api/input.go` (`PropertyDTO.UnmarshalJSON`) / `upsilonhub/internal/games/battle` (`Join`/`CreateMatch` error path)
**Affects:** any account whose equipped rolled skill contains an empty property map
serialized as `[]` (dev testuser: skill "Null_ Field _I", `targeting.Zone: []`)

---

## Summary

Two stacked defects, found during the Phase 6 E6 resurrection drill:

1. **Data quirk (Laravel-era):** PHP `json_encode` turns an empty associative
   array into `[]`. Rolled skills stored through the Laravel stack can carry
   `targeting.Zone: []` (engine emitted `{}`; PHP re-serialized as `[]`).
   The engine's `PropertyDTO.UnmarshalJSON` accepts objects and primitives but
   not `[]`, so `POST /v1/arena/start` 400s
   (`HandleArenaStart bind error: invalid property format: []`) for every
   arena including such a skill. This failed identically from Laravel — it is
   not cutover-caused.

2. **Hub follow-on:** `Matchmaker.Join` creates the `game_matches` row and
   answers `status: "matched"` with a `match_id` even when the engine start
   fails. The client lands on a match with no arena; the next
   `matchmaking/status` poll finds the arena missing, resurrection finds no
   cached board (no webhook ever fired), and the match is concluded
   ("Neural link severed"). Until that poll, further joins 409
   ("currently participating in an active match").

## Reproduction

1. Equip a character with a skill whose `instance_data` contains an empty
   property serialized as `[]` (dev DB: testuser's "Null_ Field _I").
2. `POST /api/v1/matchmaking/join` (1v1_PVE) → `matched` + match_id.
3. Engine log shows the 400 bind error; `GET /game/{id}` has an empty
   `game_state`; the SPA lands on a dead arena.

## Suggested direction

- Engine: accept `[]` as an empty `PropertyMap`/`PropertyDTO` container
  (treat as absent) — data of this shape exists in the wild.
- Hub: surface engine-start failure from `Join` (error envelope, no
  `matched` answer) and delete/conclude the just-created match row in the
  same transaction, so no zombie participation window exists.
- Optional data fix: one-time sweep normalizing `[]` → `{}` inside
  `character_skills.instance_data` property maps.

## Workaround

Unequip/delete the offending skill row (dev testuser was unequipped
2026-07-09 to unblock the E6 gate).

## Post-wipe update (2026-07-09)

Prod will be **wiped**, not adopted, at cutover (decision 2026-07-09) — so the
Laravel-era `[]` payloads (defect #1, the data quirk) vanish with the old
database and cannot recur from a fresh, hub-seeded DB. Downgraded to **Low**.

What survives the wipe is only **defect #2**: `Matchmaker.Join` answers
`matched` with a `match_id` even when the engine-start call fails, stranding the
client on an arena-less match. That is a latent robustness bug independent of
the payload shape — it would surface for *any* engine-start failure (engine down
mid-join, a future malformed loadout, etc.). Keeping the issue open for that
half: surface engine-start failure from `Join` as an error envelope (no
`matched`) and delete/conclude the just-created `game_matches` row in the same
transaction, so no zombie participation window exists.
