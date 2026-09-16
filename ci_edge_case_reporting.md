# CI Edge-Case Scenario Audit — Advancement Tracker

Audit pass under **ISS-107** (`edge_case_scenario_suite_audit`). One sub-agent per
scenario (max 3 concurrent). Each agent validates the six criteria below and, if
the scenario is inadequate, rewrites it to the simplest form that still stands at
the edge of the requirement.

**Started:** 2026-07-10 · **Owner:** Claude (orchestrator) · **Scope:** 55 active `edge_*.js` scenarios.

> **Handoff — 2026-07-10 (opencode resumes as orchestrator).** Environment re-verified live before handoff (see [Environment](#environment)). **Resume from scenario 5** (Phases 1 tail onward); also re-dispatch **#1** (C3 rewrite) and **#3** (assertion mismatch redesign). Sub-agents via `task` tool, ≤3 concurrent, one scenario per agent.
>
> **Progress 2026-07-10 (opencode wave 2).** #1, #3, #5 all re-dispatched & resolved (see table + findings). #1 → CORRECTED-GREEN but FLAKY (ISS-108: board-gen doesn't guarantee an obstacle adjacent to spawn; ~20% hit). #3 → CORRECTED-GREEN 2s (assertion was always right; scenario never isolated it). #5 → CORRECTED-GREEN 3s (phantom link + superfluous tail removed). Next: #6–#8.
>
> **Progress 2026-07-10 (Claude, orchestrator, wave 3).** Phase 1 closed out: #6 GREEN as-is, #7 CORRECTED but permanently SKIP-by-design (ISS-109: jump-height edge structurally unreachable in `1v1_PVE`, board Height range ≤ default JumpHeight), #8 CORRECTED-GREEN. Phase 2 (Attack, #9–14) fully complete — systemic finding: most Attack scenarios' `@test-link`s pointed at the wrong subsystem (phantom `mech_skill_validation_*` compound names, or real-but-wrong-domain atoms); all relinked to the actual enforcing atom (`mech_action_economy`, `mechanic_multi_entity_cell_system`, `rule_combat_range_validation`, `entity_grid`, or cross-domain reuse of `mech_move_validation` for controller checks). #10 was a full false-green rewrite that surfaced **ISS-111** (skill cooldown never decrements — real gameplay bug, High severity). #9 surfaced **ISS-110** (PVE AI initiative RNG can wipe the player's squad before any human turn, ~20% observed). All of #9–14 end CORRECTED-GREEN or GREEN.
>
> **Progress 2026-07-11 (Claude, orchestrator, wave 5 — resumed after abort).** #29 had been left mid-flight by an aborted prior session (uncommitted draft sitting in the working tree, never run/logged); re-verified from scratch rather than trusted blindly — the draft's core fix was right but incomplete (a polling-rate race meant bot 1 almost never actually observed the opponent's-turn window), now CORRECTED-GREEN 11/11 runs. Also found **#34 and #35 had abandoned uncommitted drafts** from the same aborted session — both independently re-verified and confirmed correct (CORRECTED-GREEN). Closed out the rest of Phase 6: #36–#38 fresh-audited and CORRECTED-GREEN (all shared the same bare-vs-qualified `api_character_skill_inventory` phantom-stub pattern established in #30–#35; #37/#38 also had missing prod spec-links on `unequipSkill`/`ownedCharacter`). **ISS-114 reconfirmed live** on #38 (owner account orphaned every run pre-fix via the double-`bootstrapBot` teardown-overwrite bug), worked around per #31's precedent. **ISS-102 tag on #29 was a false lead** — dropped after empirical confirmation the forfeit-out-of-turn edge never lands inside ISS-102's post-`match.found` window. Next: #39 (last Phase 6 item, same ISS-114 exposure as #38), then Phase 7 (Shop/Economy).
>
> **Handoff — 2026-07-11 (Claude, orchestrator, pausing wave 5 for context/token limits).** Since the above note: #39 closed out Phase 6 fully (CORRECTED-GREEN, ISS-114 reconfirmed again independently). Phase 7 (Shop/Economy, #40-42) fully complete — #42 was a total false-green bypass (zero API calls, same class as #32) rewritten via an admin-created cheap item to reach the 99-unit cap without the assumed 19,800 CR grind; no production bugs anywhere in Phase 7. Phase 8 (API/Envelope) in progress: #43-45 done. #43 was a scope-mismatch false green (same class as #17) — CLI transport client structurally cannot omit/spoof the request-id header, **ISS-115 filed** (distinct root cause from ISS-112, don't conflate them). #44 surfaced that malformed UUIDs deliberately 500 (not 4xx) for legacy-PHP byte-parity — the old test's dead `status_code` field check meant it never caught this. #45 was a full rewrite off a real JS `ReferenceError` bug (undefined `validCharId`) silently swallowed by its own catch. **#46 has landed and is now consolidated — Phase 8 (API/Envelope) is fully complete, no new issue filed.** Remaining: Phase 9 (Leaderboard, #47-48), Phase 10 (Admin, #49-52 — #49 is an "ISS-103 candidate" and likely shares ISS-112's harness-can't-reach-admin-negative-path limitation, per #17's precedent — check that assumption rather than re-deriving from scratch), Phase 11 (WebSocket/Realtime, #53-55). Orchestration pattern that's worked well all audit: read the target scenario file(s) first yourself to spot obvious defects, dispatch up to 3 parallel background sub-agents (one per scenario) with a detailed prompt including known suspected defects + explicit "don't touch the tracker, don't touch shared atom docs without flagging" instructions, then consolidate their reports into this tracker file yourself once they land (table row + findings-log entry) rather than letting agents write directly to avoid concurrent-edit conflicts.
>
> **Phase 3 (Auth, #15–19) fully complete.** Recurring pattern: at least 3 of 5 scenarios (#16, #17, #19) were **false greens that never tested what they claimed** — #16 (missing_token) sent a valid token anyway (auto-cached from setup) and checked a nonexistent error field; #19 (session_timeout) is the worst case found in the audit so far — its own `assert(false, ...)` failure was caught by its own enclosing catch block and silently swallowed. #17 (non_admin_access) surfaced a structural gap: the CLI harness cannot reach any admin-gated endpoint's non-admin-rejection code at all (**ISS-112** filed, likely shared with #49). #18 (password_policy_full) was a units-test-style 8-case enumeration collapsed to one sharpest edge. Notably #16 is the exact scenario the tracker's own Environment section cited as the pre-audit "smoke test" — it was green for the wrong reason from the start. A phantom atom `req_ui_session_timeout`/`requirement_req_ui_session_timeout` recurs across 5 files outside this scenario's scope — flagged as a follow-up sweep candidate, not yet actioned. Next: Phase 4 — Character/Progression (#20–24).

## Validation criteria (per scenario)

| Key | Criterion |
|---|---|
| **C1 ATD-trace** | `atd trace` (no opts) names the impacted files; `--summary` gives context. The edge case genuinely stands within / at the edge of the traced requirement. |
| **C2 ATD-docs** | Code tagged with `@spec-link` in the right place (above function or in a dedicated block *within* a function); the edge test file carries `@test-link`. |
| **C3 Scenario-simple** | The scenario is the simplest (or near-simplest) way to exercise the edge — the point where most implementations would fail. |
| **C4 Code-compliance** | The production code actually handles the edge case the scenario tests. |
| **C5 One-case-per-file** | Exactly one edge case per file. Multiple cases ⇒ must be split into multiple edge files. |
| **C6 Correction** | If the scenario is inadequate or not simple, it is rewritten. |

**Legend:** ⬜ not started · 🟦 in progress · ✅ pass · ⚠️ issue found · 🔧 corrected · ❌ blocked

## Environment

- **Stack: PROVISIONED & RUNNING** (native host, shared by all agents):
  - Postgres `postgres:18` via `docker compose up -d db` → host `:5433` (DB `postgres`, `sslmode=disable`).
  - DB reset + migrated (`hub -migrate-mode full`) + seeded (`hub -seed`, `ADMIN_INITIAL_PASSWORD=AdminPassword123!`).
  - Engine `upsilonapi` → `:8081`; Hub `upsilonhub` (`APP_DEBUG=true`) → `:8090`. `.services.pids` registered; `check_services.sh` green.
  - Caddy front door **required and running**: post-auth-extraction, `/api/v1/auth/*` is owned by `upsilonauth` and only Caddy routes both hub and auth traffic — the CLI targets it via `UPSILON_BASE_URL` (`http://proxy:8085` in compose), never the hub directly.
- **Run policy:** agents use `scripts/trigger_one_ci_test.sh <name>`, time each run (<5s target), ≤10 executions, report a status on persistent failure.
- Smoke test: `edge_auth_missing_token` PASSED in 0s.

### Key paths & tooling (for incoming orchestrator)
- **Edge scenarios:** `upsiloncli/tests/scenarios/edge_*.js` (55 active; disabled ones carry `.js.disabled`).
- **Trigger:** `scripts/trigger_one_ci_test.sh <name>` (name = filename minus `edge_` prefix and `.js`).
- **Service health:** `scripts/check_services.sh`.
- **ATD access:** `atd trace <atom_id>` (CLI, always available) **and** via the `atd` MCP server configured in `opencode.json` (`atd serve`, stdio). Use either; MCP if connected, CLI as fallback.
- **opencode config:** `opencode.json` at repo root — loads `.agent/rules/*.md` as instructions, `.agent/skills/` for skills, `gopls` LSP on, `typescript` LSP off, `atd` MCP on.

### Re-verified 2026-07-10 (opencode, pre-handoff)
- Ports listening: `:5433` (Postgres, docker `upsilon-hub-db-1`), `:8081` (`upsilonapi`), `:8090` (`upsilonhub`).
- Hub process env has `APP_DEBUG=true` and the **corrected** `UPSILON_WEBHOOK_URL=http://127.0.0.1:8090/api/webhook/upsilon` (wave-1 infra fix holds → turn-based scenarios will not hang).
- `atd trace` responsive. Stack assumed still migrated/seeded from Claude's session; if a scenario hits DB errors, re-run migrate+seed per the Stack bullets above.

---

## Progress

### Phase 1 — Movement
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 1 | edge_movement_obstacle_collision | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 | **CORRECTED, GREEN but FLAKY ~20%** (ISS-108). Removed false-green SKIPs → hard fail; strict `entity.path.obstacle` assert; single-step onto adjacent obstacle. Fails when board-gen places no obstacle adjacent to spawn |
| 2 | edge_movement_entity_collision | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **GREEN 1s** · fixed phantom+tangential test-links → `mech_move_validation`+`mechanic_multi_entity_cell_system` |
| 3 | edge_movement_already_attacked | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 | **CORRECTED, GREEN 2s** — assertion (`entity.movement.already`) was always right; redesign probes only on fresh full-credit turns (attack sets `HasMoved`; credits gate runs before `HasMoved` gate). Discovered+fixed a move+pass race |
| 4 | edge_movement_path_too_long | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED, GREEN 4s** — phantom+broad links→`mech_move_validation`; removed superfluous valid-move tail; added `move.go` spec-link above `preMoveChecks` |
| 5 | edge_movement_path_not_adjacent | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED, GREEN 3s** — phantom `mech_move_validation_path_adjacency`→`mech_move_validation`; removed superfluous valid-move tail (83→63 lines). Note: atom doc typo `notadjascent` vs code `notadjacent` |
| 6 | edge_movement_grid_boundaries | ✅ | ✅ | ✅ | ✅ | ✅ | — | **GREEN, 2s.** No corrections needed; matches corrected-scenario style already |
| 7 | edge_movement_jump_limitations | ✅ | 🔧 | ❌ | ✅ | ✅ | 🔧 | **CORRECTED, SKIP by design (ISS-109)** — jump-height edge is structurally unreachable in `1v1_PVE` (board Height range ≤ default JumpHeight); comment/log rewritten to document honestly instead of misleading "rarely" framing |
| 8 | edge_movement_wrong_controller_with_2 | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 3s** — dropped tangential `@test-link [[entity_player]]` (admin/privacy atom, unrelated to controller ownership) |

### Phase 2 — Attack
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 9 | edge_attack_already_acted | 🔧 | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 2-3s** — phantom+wrong-domain link (`mech_skill_validation_*`)→`mech_action_economy`; added missing prod spec-link + atom doc clause; strict `error_key` assert. ISS-110 filed (PVE-wipeout flake) |
| 10 | edge_attack_skill_cooldown | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, ~4s** — was false-green (coin-flip branch, unrelated failure logged PASSED); full rewrite to deterministic single-case cast→cooldown-reject. ISS-111 filed (cooldown never decrements, High) |
| 11 | edge_attack_target_no_entity | 🔧 | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, ~2s** — relinked to `mechanic_multi_entity_cell_system` (no dedicated attack-validation atom exists, ATD gap flagged); added missing prod spec-link + strict `error_key` assert; SKIP→hard fail |
| 12 | edge_attack_target_not_in_range | 🔧 | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | **CORRECTED-GREEN, 2-3s** — relinked to `rule_combat_range_validation`; was a false green testing occupancy (dup of #11), not range — rewrote to target farthest live foe, strict `entity.attack.outofrange` assert |
| 13 | edge_attack_target_out_of_grid | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 1-3s** — phantom link→`entity_grid`; added missing prod spec-link; removed dead second block that silently absorbed unrelated failures; strict `error_key` assert added. Post-audit CI showed it IS ISS-110-exposed (pre-turn squad wipe), contra the original note — see findings log |
| 14 | edge_attack_wrong_controller_with_2 | 🔧 | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, ~3s** — relinked to `mech_move_validation` (shared `CheckControllerForEntity`, same reuse pattern as #11); dropped phantom+tangential links; added missing prod spec-link |

### Phase 3 — Auth
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 15 | edge_auth_invalid_credentials | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1s** — dropped phantom `[[req_security_authorization]]` link; anti-enumeration behavior (identical 401 for bad account/password) verified correct |
| 16 | edge_auth_missing_token | 🔧 | 🔧 | 🔧 | 🔧 | 🔧 | 🔧 | **CORRECTED-GREEN, 0s** — was a total false green (registered first, so a valid token was auto-sent; assertion checked a nonexistent field). Full rewrite: unauthenticated call, strict 401 assert. Notably, this is the scenario the tracker's own smoke test called "PASSED in 0s" pre-audit |
| 17 | edge_auth_non_admin_access | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN (harness-layer only), <1s** — server-side branch is structurally unreachable via CLI (ISS-112 filed); rewrote to pin the harness-guard behavior honestly, fixed 2 nonexistent-route bugs + dead `status_code` assertions |
| 18 | edge_auth_password_policy_full | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0s** — 8 near-duplicate sub-cases collapsed to one worst-case password violating all 4 policy dims at once; dropped out-of-scope confirmation-mismatch case (different validator, not migrated — note for future coverage check) |
| 19 | edge_auth_session_timeout | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 0-1s** — worse than false-green: scenario's own failure assertion was caught by its own catch block and swallowed. Rewrote via logout→reuse-dead-token→401. Phantom link `req_ui_session_timeout` also found in 5 other files (sweep candidate) |

### Phase 4 — Character / Progression
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 20 | edge_char_reroll_limit | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, ~2s** — phantom `mech_character_reroll_limit`/`us_character_reroll_reroll_counter` + tangential `uc_player_registration` → `upsilonbattle:mech_character_reroll`+`us_character_reroll`; fixed assert-inside-own-catch self-swallow bug on the 4th-reroll rejection, added strict `assertResponse(e, 403, "Reroll limit reached.")` |
| 21 | edge_char_reroll_post_match | ✅ | 🔧 | 🔧 | ❌ | 🔧 | 🔧 | **CORRECTED, RED (blocked by ISS-113), ~3-4s** — was calling `character_rename` instead of `character_reroll` (didn't test reroll at all); its own `assert(false)` was also swallowed by its own enclosing catch (same anti-pattern as #19). Rewritten to exercise the real endpoint; the corrected assertion then deterministically (3/3 runs) surfaces a genuine production gap: `reroll()` has no post-match/creation-flow gate at all. ISS-113 filed (Medium) |
| 22 | edge_prog_attribute_cap | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 0s** — total false green: fabricated cap formula (`10+wins` on raw stats) + nonexistent field `char.move` (real: `movement`) → NaN poisoned every value, dead valid-upgrade branch, no error-key check; rewrote to real CP formula (`100+wins*10` on `spent_cp`), no match-play needed, strict `assertResponse(e, 400, exact message)` |
| 23 | edge_prog_movement_gate | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-1s** — total false green: tested for a movement-gate-below-5-wins mechanic that `rule_progression` v2.1 explicitly documents as removed ("the legacy once every 5 wins Movement gate is removed... self-balances via its 30 CP cost"); the real call succeeds, so the scenario's own `assert(false, ...)` was caught by its own enclosing catch block and logged as "properly rejected" (same swallow pattern as #19). Phantom link `[[us_win_progression_movement_locked]]` removed; dropped `[[us_win_progression]]` (real but 0 code_links, wrong-domain UI story). Rewrote to the real edge: fresh 0-win character successfully buys +1 Movement (30 CP, within the 100 CP cap) — a regression guard against the gate ever being reintroduced, strict `assertEquals` on `movement`/`spent_cp`. Removed a dead unasserted HP-upgrade tail (C5). No production bug — `profile.go` and the atom doc were already correct. |
| 24 | edge_prog_negative_value | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-1s** — dropped tangential `[[entity_character]]` (in-game battle-entity schema, same wrong-domain pattern as #12/#22) → single `[[rule_progression]]`; added missing prod spec-link on `validateUpgrade` (the actual non-negativity enforcement point, separate from `upgrade()`'s cap-check header tag); collapsed 3 near-duplicate negative-stat sub-cases + a dead non-asserting zero-value branch to one sharpest edge (HP delta -1); replaced bare `e.message` logging with strict `assertResponse(e, 422, "Validation failed")` + exact `meta.errors["stats.hp"]` message check; fixed stale `char.move` (real field: `movement`) |

### Phase 5 — Matchmaking
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 25 | edge_match_invalid_game_mode | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-3s** — phantom `req_matchmaking_matchmaking_queue` + wrong-domain `spec_match_format` → relinked to `[[shared:req_matchmaking]]`+`[[upsilonapi:api_matchmaking]]`; added missing prod spec-link to `validateJoin`; collapsed 4-value enumeration to one sharpest edge (`1v3_PVP`); dead `e.status_code` check removed, strict `assertResponse(e, 422, ...)` + exact `meta.errors.game_mode` added; dropped bundled unrelated queue-lifecycle case + redundant manual teardown |
| 26 | edge_match_leave_not_queued | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 2-3s** — dropped phantom `[[usecase_api_flow_matchmaking]]` (real-but-wrong-domain sibling `us_api_flow_matchmaking` also considered, dropped); catch-all try/catch that accepted success OR error replaced with a direct un-caught call (`LeaveQueue` is an unconditional DELETE, always succeeds — a thrown error would now be a real regression); dropped bundled unrelated join+leave tail (C5), already covered by `edge_match_queue_while_queued.js` |
| 27 | edge_match_queue_while_queued | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 1-3s** — phantom `usecase_api_flow_matchmaking` dropped, kept+qualified `rule_matchmaking_single_queue`+`api_matchmaking`; fixed assert-inside-own-catch self-swallow bug (same anti-pattern as #19/#21/#23/#24) via outer `rejected` flag; dead `e.status_code` check → strict `assertResponse(e, 409, "Conflict: You are already in a matchmaking queue.")`; dropped bundled leave→idle→rejoin tail + redundant manual teardown |
| 28 | edge_match_queue_while_in_match_with_2 | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 2-3s** — added missing prod spec-link (`ErrInActiveMatch` had none, unlike sibling `ErrAlreadyQueued`); collapsed bundled forfeit+requeue tail (also a noisy 2-bot race) to the single named edge; loose `assertEquals(e.status,409,...)` → strict `assertResponse` with exact message; dropped redundant manual teardown |
| 29 | edge_match_forfeit_out_of_turn_with_2 | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 2-4s** (11/11 runs) — dropped phantom `[[mech_initiative]]`; fixed a sampling-bias race (bot 0 reacts near-instantly via SSE, bot 1 polled too slowly to ever observe the opponent's-turn window). **ISS-102 does not apply** (confirmed empirically — forfeit lands turns after game start, not in the post-`match.found` window). ⚠️ **Flagged for human review** — sub-agent's own audit, not independently cross-checked by the orchestrator like earlier waves; timing-race fix (poll rate, round caps) is inherently sensitive to CI-runner load and worth a human skim before trusting long-term |

### Phase 6 — Equipment / Skills
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 30 | edge_equip_unowned_character | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1-4s** — phantom `[[api_character_equip]]` → `[[upsilonapi:api_equipment_management]]`; loose `e.status === 403 \|\| 404` OR-assertion tightened to strict `assertResponse(e, 403, "This action is unauthorized.")`. No production bug |
| 31 | edge_equip_unowned_item | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1-2s** — phantom `[[api_character_equip]]`→`[[upsilonapi:api_equipment_management]]`; loose `e.status===403\|\|404` → strict `assertResponse(e,403,"Inventory item does not belong to you.")` + `meta.reason==="inventory_not_owned"`. Surfaced ISS-114 (harness bug: `bootstrapBot` teardown hook is single-slot, overwritten by a 2nd call — account leak/mislabel; affects #30/#34/#39) |
| 32 | edge_equip_wrong_slot | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 2-3s** — was a total false green with zero API calls/assertions (pure "let's assume..." reasoning comments ending in an unconditional BYPASS pass); equip endpoint has no client-facing slot param (slot always inferred, atom explicitly forbids client-supplied slot) so "wrong slot" is structurally impossible there — rewrote to the one genuine wrong-slot edge, unequip's invalid-slot-name 422, distinct from #33's valid-but-empty-slot 404; phantom `[[rule_equipment_slot_validation]]` → `[[upsilonapi:api_equipment_management]]`; added missing 422/invalid_slot clause to the atom doc |
| 33 | edge_unequip_empty_slot | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 2-3s** — only defect was a phantom self-referential `@test-link [[api_character_unequip]]` → fixed to `[[upsilonapi:api_equipment_management]]`. Confirms #32's distinction holds: valid-but-empty-slot 404, distinct from #32's invalid-slot-name 422. No production bug |
| 34 | edge_skill_equip_invalid_id | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1-3s** (5/5 runs) — qualified test-link to `[[upsilonapi:api_character_skill_inventory]]`; fixed assert-inside-own-catch; exact 404 message verified live incl. DEBUG-mode prefix handling |
| 35 | edge_skill_slot_full | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 0-2s** (5/5 runs) — qualified test-links; fixed assert-inside-own-catch; strict `assertResponse(e,422,"All 1 skill slot(s) are occupied.")` + `meta.reason==="ERR_SKILL_SLOT_FULL"`; slot formula `min(5,1+wins/10)` verified exact |
| 36 | edge_skill_template_not_found | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, ~2-3s** (5/5 runs) — bare `api_skill_template_browse` phantom-stub → qualified `upsilonapi:api_skill_template_browse`; added missing spec-link to `showTemplate`; fixed assert-inside-own-catch |
| 37 | edge_skill_unequip_not_equipped | ✅ | 🔧 | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1-3s** (5/5 runs) — same bare-ID fix; added missing spec-link to `unequipSkill` (had zero, unlike siblings); fixed assert-inside-own-catch |
| 38 | edge_skill_unowned_character_equip | ✅ | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | **CORRECTED-GREEN, 1-3s** (5/5 runs) — qualified link; added missing spec-link to `ownedCharacter`; assertion only coincidentally passed (`"unauthorized"` substring-matched the real message) → tightened to exact `"This action is unauthorized."`; **ISS-114 confirmed live** (owner account orphaned every run pre-fix), worked around per #31's precedent |
| 39 | edge_skill_unowned_character_roll | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1-5s** (5/5 runs) — qualified link, dropped tangential `rule_character_skill_slots` (governs capacity not ownership); assertion only coincidentally passed → tightened to exact `"This action is unauthorized."`; **ISS-114 reconfirmed live**, same #31/#38 workaround applied. Closes out Phase 6 |

### Phase 7 — Shop / Economy
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 40 | edge_shop_insufficient_credits | ✅ | ✅ | 🔧 | 🔧 | ✅ | 🔧 | **CORRECTED-GREEN, 1-3s** (5/5 runs) — dropped total-phantom `rule_credit_spending_shop`; collapsed 6-call spend-down to a single deterministic over-budget purchase (mirrors #22); strict `assertResponse(422, exact message)` + `meta.reason==="insufficient_credits"` |
| 41 | edge_shop_unknown_item | ✅ | ✅ | ✅ | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1-3s** (5/5 runs) — qualified test-link; confirmed 404 uses non-DEBUG-prefixed literal message (assertion was correctly strict already); assert-inside-own-catch fixed per convention (verified not an active swallow) |
| 42 | edge_quantity_cap_99 | ✅ | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | **CORRECTED-GREEN, 1-3s** (5/5 runs) — total false green (zero API calls/assertions, unconditional BYPASS) rewritten via admin-created 1-credit item to reach the 99-unit cap cheaply, no 19,800 CR grind needed; added missing prod spec-link + fixed stale atom-doc test reference. No production bug |

### Phase 8 — API / Envelope
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 43 | edge_api_missing_request_id | ✅ | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | **CORRECTED (harness-layer only), GREEN, 1-3s** (5/5 runs) — total scope-mismatch false green rewritten; CLI transport client structurally cannot omit/spoof the request-id header (distinct root cause from ISS-112) → **ISS-115 filed**; rewrote to pin the one observable thing (request_id round-trips through error envelope) |
| 44 | edge_api_invalid_uuid | ✅ | 🔧 | 🔧 | 🔧 | 🔧 | 🔧 | **CORRECTED-GREEN, 1-3s** (5/5 runs) — dropped tangential `entity_character`; real behavior is a deliberate **500** (byte-parity w/ legacy PHP), not 4xx as the old dead `status_code` check assumed; 7-value enumeration collapsed to one case |
| 45 | edge_api_malformed_json | ✅ | ✅ | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-1s** (5/5 runs), full rewrite — confirmed a real JS `ReferenceError` (undefined `validCharId`) silently swallowed by its own catch; no way to inject genuinely malformed JSON via CLI; landed on `character_upgrade` non-numeric `hp` as the real sharpest edge |
| 46 | edge_api_5xx_error_handling | ✅ | ✅ | 🔧 | 🔧 | 🔧 | 🔧 | **CORRECTED (harness-layer), GREEN, 0s** (5/5 runs) — no genuinely new 5xx trigger exists (9 sites all reuse #44's already-covered `uuid.Parse`→panic→500 mechanism); reframed to strict envelope-shape assertions on a real 401, dropped soft `if(e.field)` duck-typing. **Closes Phase 8.** No issue filed |

### Phase 9 — Leaderboard
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 47 | edge_leaderboard_invalid_mode | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 1-2s** (5/5 runs) — bare `api_leaderboard`→qualified; dropped phantom `us_leaderboard_view_sort_leaderboard`; added missing prod spec-link to `validateLeaderboard`; 6-value enumeration collapsed to 1; dead `e.status_code` → strict `assertResponse(422,"Validation failed")` + `meta.errors.mode` |
| 48 | edge_leaderboard_over_pagination | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 0-3s** (6/6 runs) — bare→qualified link, dropped phantom `us_leaderboard_view_sort_leaderboard`; false-tolerant try/catch (dead 404 branch, page=9999 always 200/empty per `leaderboard.go:144-149`) replaced with unconditional strict assert + `meta.current_page`/`total` consistency check. No production bug |

### Phase 10 — Admin
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 49 | edge_admin_private_data_access | 🔧 | 🔧 | 🔧 | ❌ | 🔧 | 🔧 | **CORRECTED, RED (blocked by ISS-116), <1s** (3/3 deterministic) — rewrote to the atom's real content (admin field censorship), reachable via `adminSection` unlike the non-admin-rejection half (harness-blocked, ISS-112). Real prod bug: `newUserJSON` never censors `full_address`/`birth_date` for admin views. **ISS-116 filed (Medium)** — supersedes the tracker's earlier "ISS-103 candidate" guess, which was wrong (ISS-103 is an unrelated foe-loadout masking issue) |
| 50 | edge_admin_anonymize_nonexistent | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-1s** (5/5 runs) — total scope-mismatch false green (never called anonymize); rewritten via `adminSection`+`admin_user_anonymize` on a garbage account_name → strict 404 `"No query results for model [App\Models\User] ..."`; dropped 0-coverage `rule_gdpr_compliance`. Admin-positive path, not ISS-112's non-admin-rejection path — distinct from #49 |
| 51 | edge_admin_delete_nonexistent | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-1s** (8/8 runs) — same false-green class as #50, rewritten via `adminSection`+`admin_user_delete`; kept qualified `rule_gdpr_compliance` (this file, not #50's, is the one it actually lists in its own `test_links`); added missing prod spec-link to `destroy()` (`admin.go:93-96`, had none unlike sibling `anonymize()`) |
| 52 | edge_admin_skill_template_not_found | ✅ | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-1s** (8+ runs) — bare→qualified link; misplaced `@spec-link` inside the test file removed, real gap fixed at the source (`jsAdminSection`, `bridge_battle.go:602`, had zero spec-link — now the one canonical fix for all 8+ files referencing this atom); 3 verb sub-cases (GET/PUT/DELETE, byte-identical via shared `findSkillTemplate` guard) collapsed to 1 (GET). **Phase 10 (Admin, #49-52) now fully complete** |

### Phase 11 — WebSocket / Realtime
| # | Scenario | C1 | C2 | C3 | C4 | C5 | C6 | Disposition |
|---|---|---|---|---|---|---|---|---|
| 53 | edge_ws_connection_no_token | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 0-1s** (10/10 runs) — protocol is SSE not WS; rewrote to `Listener.Sync()`'s own client-side no-token short-circuit via `wsConnect()`/`wsStatus()`; dropped phantom `req_security_authorization`→`req_security`; added missing spec-link to `Sync()`; baseline was an assert-inside-own-catch false green (same class as #19/#21/#23/#24/#27) plus a dead call to the retired `/help` route |
| 54 | edge_ws_wrong_channel | ✅ | 🔧 | 🔧 | ✅ | ✅ | 🔧 | **CORRECTED-GREEN, 1-3s** (7/7 runs) — pivoted "wrong channel" to its SSE analogue (forged `Last-Event-ID` replay-authorization), per the ATD index's own `test_links` hint; live raw-curl proof confirms `IsParticipant` correctly denies cross-user replay (byte-identical to no-id at all — no production bug, a correctly-enforced security property); harness can't forge `Last-Event-ID` itself, so file pins the legitimate reconnect/replay path with the denial proof recorded as verified evidence in the header (3rd harness-layer-ceiling instance this audit); dropped dead `ws_channel_key` (column dropped in migration 000002) |
| 55 | edge_ws_ping_timeout | 🔧 | 🔧 | 🔧 | ✅ | 🔧 | 🔧 | **CORRECTED-GREEN, 1-3s** (10/10 runs) — pivoted "ping/pong timeout" to the SSE-era analogue (fresh `request_id` per async broadcast frame, per `req_logging_traceability`'s own `test_links` hint); literal heartbeat-survival edge (25s cadence, no test-time override wired into the running binary) judged impractical for this suite's budget, documented not force-tested (ISS-109 precedent); added missing spec-link to `sse.BoardFrame`/`MatchFoundFrame`. **Closes Phase 11 and the entire 55-scenario ISS-107 audit** |

---

## Disabled scenarios (out of active scope, noted for completeness)
- edge_attack_out_of_turn_with_2.js.disabled
- edge_match_action_after_end_with_2.js.disabled
- edge_movement_out_of_turn_with_2.js.disabled
- edge_prog_allocation_no_wins.js.disabled

---

## Findings log

### ⚑ CROSS-CUTTING WATCH (wave 3, flagged by #11's agent) — Phase 2 Attack scenarios may be spec-linked to the wrong subsystem
Sibling scenarios #9, #10, #12–#14 reportedly carry a `mech_skill_validation_*` phantom-compound-name
test-link pattern, but the real base atom `mech_skill_validation` documents `skill_validation.go`
(skill casts) exclusively — not `attack.go`/`attack_checks.go` (basic attacks). If those scenarios
actually test basic-attack rejections (per filenames), the whole cluster may be linked to the wrong
subsystem entirely, not merely phantom-named. Also: no dedicated "attack validation" atom exists yet
(unlike `mech_move_validation` for movement) — `entity_no_entity`/no-target case for #11 was correctly
relinked to `mechanic_multi_entity_cell_system` (the same mechanism used for movement scenario #2), but
range/cooldown/action-economy edges may need their own atom or a different existing one. **Dispatched
agents for #9/#10/#12–#14 should verify against the real enforcing Go file first, not assume the
existing test-link's subsystem is correct.**

### edge_attack_already_acted — CORRECTED-GREEN, ISS-110 filed (wave 3)
- C1 🔧 `mech_action_economy` genuinely traces (Attack() carries the tag), but no atom enumerates the attack-side "already acted" gate the way `mech_move_validation`/`mech_skill_validation` do for their domains — doc gap, not fabricated.
- C2 🔧 confirmed phantom `[[mech_skill_validation_action_state_verification]]`; even resolved to base `mech_skill_validation`, it's the **wrong domain** (governs `skill_validation.go`'s `entity.alreadyacted`, not `attack_checks.go`'s `entity.hasacted`) — confirms the cross-cutting watch flagged by #11. Fixed to `[[mech_action_economy]]`. `preAttackChecks` had zero `@spec-link` (sibling `preMoveChecks`/`preSkillChecks` both tag their header) → added. Also added a "Single-Action Enforcement (Attack)" clause to `mech_action_economy.atom.md`.
- C3 🔧 catch block accepted any thrown error as pass, no key check → added strict `assertEquals(error_key, "entity.hasacted")`.
- C4 ✅ `attack_checks.go:95-99` rejects correctly, unit-covered by `rules_attack_failure_test.go:190-210`. C5 ✅ single edge case.
- **Disposition: CORRECTED-GREEN, 2-3s** (8 runs: 4/5 baseline passed, 1 unrelated PVE-wipeout failure; 3/3 post-fix passed).
- **ISS-110 filed (Medium)** — ~1/5 runs, PVE AI wipes the player's whole squad before any human turn (independent per-entity random initiative, `ruler.go:195`, no player-first safeguard). Distinct mechanism from ISS-108/109 (initiative RNG, not terrain RNG) but same class of risk; can block any `edge_attack_*`/`edge_movement_*` scenario requiring survival to act.

### edge_attack_skill_cooldown — CORRECTED-GREEN, ISS-111 filed (wave 3)
- C1 ✅ `mech_skill_validation` check #4 (Cooldown Check, `skill.cooldown`) exactly on-point.
- C2 🔧 3 test-links trimmed to one: phantom compound-name link removed; tangential `mech_combat_attack_computation` removed; `domain_skill_system` removed despite matching prose (zero `code_links`/`test_links` in `atd_trace` — no production code actually carries its spec-link, fails "names impacted files"). Fixed a duplicate consecutive `@spec-link [[mech_skill_validation]]` in `skill_validation.go` above `checkSkillCost`.
- **C3/C5 🔧 was a false green, not just non-simple:** coin-flip branch tested two unrelated mechanics with no real assertion; fresh characters always have 0 skills so it always hit the fallback, which itself failed for an unrelated reason (`entity.attack.outofrange`) yet still logged PASSED. Full rewrite: admin-created deterministic active/EnemyOnly skill (avoids passives, which skip the cost/cooldown check) → cast → pass turn → cast again → strict `assertEquals(error_key, "skill.cooldown")`.
- C4 ✅ `skill_validation.go:207-210` rejects reuse correctly; verified live.
- **Disposition: CORRECTED-GREEN, ~4s** (3 stable passes; convergence took ~13 runs due to own bugs + ISS-110 PVE-initiative RNG, mitigated via a Defense buff on the caster).
- **ISS-111 filed (High)** — `sk.Cooldown` is set on cast (`skill_validation.go:248`) but **never decremented anywhere in the repo** (confirmed by repo-wide grep, both by the sub-agent and independently by the orchestrator). `BuffTickDown` is the only tick-down primitive and is dead in production (test-only call site). Once cast, any active skill is permanently locked for the rest of the match — likely a real gameplay-balance regression, not intended (property doc explicitly describes a decrementing counter).

### edge_attack_target_out_of_grid — CORRECTED-GREEN (wave 3)
- C1 ✅ `entity_grid`'s boundary-check doc directly on-point (`grid.go:181-183` `PositionIsInGrid`, used by `CellAt` at `attack_checks.go:38`).
- C2 🔧 confirmed phantom `[[mech_skill_validation_grid_boundaries_verification]]` (matches predicted cross-cutting pattern) → removed, kept real `[[entity_grid]]`. `preAttackChecks` only had the whole-function `[[mech_action_economy]]` header (documents unrelated `HasActed` gate) → added dedicated `@spec-link [[entity_grid]]` above the boundary-check block (`attack_checks.go:36-41`).
- C3 🔧 catch block only logged the error, never asserted `error_key` → added strict `assertEquals(..., "entity.attack.target.invalid", ...)`.
- C4 ✅ `attack_checks.go:38-41` rejects via `Grid.CellAt`→`PositionIsInGrid`; verified live.
- C5 🔧 removed a dead second "attack enemy in-grid" block whose catch just logged "may be expected" either way — it silently absorbed an unrelated `entity.attack.outofrange` failure in the baseline run without flagging it.
- **Disposition: CORRECTED-GREEN, 1-3s** (4 runs, no flakiness — deterministic, single-turn, not subject to ISS-108/ISS-110). No new defects.
- **Correction (2026-07-12, post-audit CI run `29192473723`):** the "not subject to ISS-110" claim above was wrong — the scenario joins `1v1_PVE` and must survive to its first `waitNextTurn()`, so it IS in ISS-110's blast radius like every other survival-dependent attack/movement scenario. CI hit exactly that: squad wiped pre-turn (player's 30-HP characters dead at 0 HP, PVE monsters untouched), `waitNextTurn()` returned null → "Match ended unexpectedly". Known-class flake, not a defect in the rewrite; the assertion logic itself is still deterministic once the bot survives to act.

### edge_attack_target_not_in_range — CORRECTED-GREEN (wave 3)
- C1 🔧 all existing links wrong: `mech_skill_validation_range_limit_verification` phantom; `mech_combat_attack_computation` real but wrong domain (damage math, zero code_links); `entity_character` tangential (stat schema). Correct atom is `rule_combat_range_validation` — already properly spec-linked in prod (`attack_checks.go:64`), clean ancestry, logic text matches code exactly. Was Impl=1/Tests=0 (genuinely undertested) before fix.
- C2 🔧 scenario header rewritten to the single real `[[rule_combat_range_validation]]`; prod spec-link placement was already correct.
- **C3/C4 🔧 real bug in the test, not the engine:** original targeted a far *empty* cell — occupancy check (`entity.attack.noentity`) fires before range check, and the catch never checked `error_key`, so it was a false green duplicating scenario #11's edge rather than testing range at all. Rewrote to target the actual farthest live foe entity, strict `assertEquals(error_key, "entity.attack.outofrange")`. Confirmed default `AttackRange=1` for unequipped characters, so any non-adjacent foe is provably out of range.
- C5 ✅ one edge case, no dead branches.
- **Disposition: CORRECTED-GREEN, 2-3s** (8 runs total: 4 baseline + 4 post-fix, all showing exact `entity.attack.outofrange`). No production code changes needed. No new defect.

### edge_attack_wrong_controller_with_2 — CORRECTED-GREEN (wave 3)
- C1 🔧 `mech_action_economy` confirmed wrong domain (its own text, added by #9's fix, explicitly disclaims covering `entity.controller.mismatch`). No dedicated attack-validation atom exists. Relinked to `mech_move_validation` check #3 (Controller Mismatch) — same shared `gamestate.CheckControllerForEntity` used by move/attack/skill/pass, same cross-domain-reuse resolution style as #11's `mechanic_multi_entity_cell_system` fix. ATD gap confirmed, not fabricated.
- C2 🔧 dropped phantom `mech_skill_validation_turn_controller_identity_verification` (confirmed non-existent, stale index artifact) + tangential `entity_player` (GDPR/identity atom, same conclusion as sibling #8) → single `[[mech_move_validation]]`. Added missing dedicated in-function spec-link in `attack_checks.go:26-29` (previously relied only on the wrong-domain function-header tag).
- C3 ✅ mirrors `edge_movement_wrong_controller_with_2`'s accepted pattern exactly — already near-simplest (controller check runs first, target correctness irrelevant).
- C4 ✅ `entity.controller.mismatch` verified pre/post-fix. C5 ✅ single edge case.
- **Disposition: CORRECTED-GREEN, ~3s** (3 stable runs). Confirms cross-cutting watch for this scenario specifically; #12/#13 touched different checks (range, out-of-grid) so no cross-application needed there.

### edge_auth_invalid_credentials — CORRECTED-GREEN (wave 3)
- C1 ✅ `api_auth_login`/`uc_player_login` both real, correct ancestry/code_links (`upsilonhub/internal/gateway/auth.go`).
- C2 🔧 dropped phantom `[[req_security_authorization]]` (no such atom exists anywhere, only referenced from scenario files). Prod spec-link already correctly placed.
- C3 ✅ strict `assertResponse(e, 401, "Invalid credentials.")`, not a broad catch. C4 ✅ `auth.go:63-68` deliberately returns identical generic 401 for both bad-account and bad-password (anti-enumeration), matching atom's stated boundary.
- C5 ✅ judgment call: wrong-password + wrong-account both hit the same branch/message — one cohesive anti-enumeration edge, not two mechanics; closing valid-login block is a real sanity check, not a dead tail.
- **Disposition: CORRECTED-GREEN, 1s** (2 runs). No new defects; also unit-covered (`auth_test.go:78`).

### edge_auth_missing_token — CORRECTED-GREEN, was a total false green (wave 3)
- ⚑ **Notable:** this is the exact scenario the tracker's Environment section cites as the pre-audit smoke test ("PASSED in 0s") — it was passing for entirely the wrong reason the whole time.
- C1 🔧 relinked to `req_security` (Sanctum Token Security Requirement) — real, exact match, already lists this scenario in its own `test_links`.
- C2 🔧 both original links bad: `req_security_authorization` phantom; `mechanic_frontend_auth_bridge` real but wrong-domain (SPA Axios/localStorage bridge, 0% impl/test coverage — not the Go/Laravel backend gate this CLI test drives). Production `RequireAuth()` had **zero** spec-link despite sibling functions (`TokenRenewal`, `RequireAdmin`) both carrying one → added.
- **C3/C4 🔧 total false green:** scenario called `auth_register` first, which auto-caches the returned token client-side (`AuthRegister.Execute` → `sess.SetToken()`) — so the "no-login" follow-up call sent a valid Bearer token anyway (confirmed live via curl log). The catch branch also treated success as acceptable, and the intended assertion checked `e.status_code`, a field that doesn't exist on the CLI's thrown error object (`bridge.go` sets `status`) — never fired either way, by two independent mechanisms.
- C5 🔧 file bundled four unrelated checks (register, no-login access, a public `help_endpoint` call throwing `unknown route` — dead code from the retired `/help` route per the Phase 6 cutover — and post-login access). Trimmed to one edge.
- C6 🔧 full rewrite: fresh unauthenticated agent, direct `profile_get` call, strict `assertEquals(e.status, 401, ...)`.
- **Disposition: CORRECTED-GREEN, 0s** (4 stable runs). Production code (`RequireAuth`/`bearerToken`) was already correct — bug was entirely in the test.

### edge_auth_non_admin_access — CORRECTED-GREEN (harness-layer only), ISS-112 filed (wave 3)
- C1 ✅ `uc_admin_login` traces cleanly, step 2 is exactly the negative edge under test.
- C2 🔧 2 of 3 links wrong-domain: `rule_admin_access_restriction` is spec-linked in prod to `RequireAdmin()` middleware (different route family, owned by #49) not `adminLogin()`; `req_admin_experience` overly broad. Reduced to `[[uc_admin_login]]`, matching `adminLogin()`'s real spec-link. No prod code changes needed.
- **C3 🔧 structurally blocked, not just non-simple:** original called nonexistent routes (`auth_admin_login`→real name `admin_login`; `admin_dashboard` never existed as an API route) and both catches checked `e.status_code`, a field that never exists on any thrown error — dead assertion independent of the routing bug. Fixing the route name doesn't help: `bridge.go:110` hard-blocks any `admin_`-prefixed route outside `adminSection()`, and `adminSection()` only ever authenticates as the real seeded admin — **no scripting path exists to call an admin route as a non-admin.** Confirmed deterministic (3/3 runs), not flaky.
- C4 ✅ verified live via raw curl (bypassing CLI): `POST /api/v1/auth/admin/login` as non-admin → real `403`, `auth.go:100-103`. Server code correct, but zero test coverage anywhere (no Go unit test, no reachable E2E path).
- C5 🔧 removed dead `admin_dashboard` sub-case + redundant tail → one edge case.
- C6 🔧 rewrote to pin the one thing actually observable (harness-layer block), honest header documenting it only proves the harness's guard, not the server's rejection.
- **Disposition: CORRECTED-GREEN (harness-layer only), <1s** (3/3 runs, deterministic).
- **ISS-112 filed (Medium)** — CLI harness structurally blocks negative-path testing of any admin-gated endpoint; likely same root cause affects #49 (`edge_admin_private_data_access`, already an "ISS-103 candidate"). Recommends a Go unit test as interim coverage + a scripting escape hatch (e.g. `callAsNonAdmin`) long-term.

### edge_auth_password_policy_full — CORRECTED-GREEN (wave 3)
- C1 ✅ `rule_password_policy` real, logic (min 15, uppercase, digit, symbol) matches code exactly.
- C2 🔧 dropped over-broad `[[req_security]]`/`[[uc_player_registration]]` → single precise `[[rule_password_policy]]`. Prod `checkPasswordPolicy` already tagged, but the 15-char floor call site had no dedicated tag → added.
- **C3/C5 🔧 was enumeration, not one edge:** 8 near-duplicate sub-cases (unit-test-style sweep) including an unrelated mechanic (password *confirmation* mismatch, a different validator, not part of `rule_password_policy`). Collapsed to one sharpest edge: single password violating all 4 policy dimensions at once, proving the server accumulates/reports every violation rather than short-circuiting. Per-dimension sweep coverage already exists elsewhere (`e2e_password_policy.js`); confirmation-mismatch dropped as out-of-scope/wrong-domain, not migrated — worth a coverage check later, not blocking.
- C4 ✅ verified empirically: all 4 violation messages present in `meta.errors.password`; original 8 sub-cases had no false-greens either (each assertion was genuinely earned).
- **Disposition: CORRECTED-GREEN, 0s** (3 runs, stable). No new defect.

### edge_auth_session_timeout — CORRECTED-GREEN (wave 3)
- C1 🔧 only `req_security_token_ttl` genuinely on-point (already lists this scenario in its own `test_links`). Second link `[[requirement_req_ui_session_timeout]]` phantom-ID (real form `req_ui_session_timeout` is an `upsilonbattleui` frontend atom, 0% impl/test coverage, structurally unreachable from a backend CLI scenario — same wrong-domain pattern as #16's `mechanic_frontend_auth_bridge`).
- C2 🔧 dropped phantom+wrong-domain link. `AuthenticateToken` (`upsilonhub/internal/platform/identity/pg.go:187`) — the actual enforcement point, and one of the atom's own listed `code_links` — had zero spec-link → added.
- **C3/C4 🔧 worse than a false green:** `upsilon.setContext("test_no_auth", true)` is a complete no-op (never read anywhere in the CLI; Authorization header always comes from `Session.Token()`) — so the "unauthenticated" call actually succeeded with the still-valid token, firing the scenario's own `assert(false, ...)`, which was then **caught by its own enclosing catch block** (accessed nonexistent `.message`/`.status_code`, both silently undefined) — swallowing the failure and logging PASSED. Dead `expiredToken` variable hinted at a never-implemented design. No test seam exists to fabricate/backdate a token (confirmed via search).
- **Rewrite:** register → confirm live token works → `auth_logout` (revokes server-side without clearing the CLI's cached token) → reuse the now-dead token → strict `assertEquals(e.status, 401, ...)`. Hits the exact same `AuthenticateToken`/`ErrUnauthenticated` path a real expiry would. TTL clock math itself separately covered by fake-clock Go unit tests (`token_renewal_test.go`).
- C5 ✅ single edge case (dead-session-token rejection), distinct from #16 (never-authenticated).
- **Disposition: CORRECTED-GREEN, 0-1s** (4/4 runs). No production bug — code already correct; bug was entirely in the test.
- **Follow-up sweep candidate (not fixed):** the phantom `[[requirement_req_ui_session_timeout]]` link also appears in `e2e_session_timeout.js`, `tests/edge_case_report.sh:61`, `tests/ci_report.sh:95`, `edge_case_report.md:26`, `CI.md:155` — same non-existent/wrong-domain atom repeated across 5 other files, out of this scenario's scope.

### edge_attack_target_no_entity — CORRECTED-GREEN (wave 3)
- C1 🔧 original links (`mech_combat_attack_computation`, `entity_character`) were off-topic (damage math / character schema, not the empty-tile pre-check) → relinked to `mechanic_multi_entity_cell_system` (same entity-presence-in-cell mechanism as movement scenario #2's fix). No dedicated attack-validation atom exists — flagged as ATD gap.
- C2 🔧 scenario header → single real `@test-link`; production `preAttackChecks` had **zero** `@spec-link` on the actual gating block (`attack_checks.go:47`) — added one, dedicated in-function block per convention.
- C3 🔧 assertion caught the exception but never checked `error_key` → added strict `assertEquals(..., "entity.attack.noentity", ...)`; converted silent "no empty tile" SKIP into hard `assert`. Occupancy check fires before range check, so target distance is irrelevant — already near-simplest otherwise.
- C4 ✅ empirically verified exact `entity.attack.noentity` both before/after. C5 ✅ single edge case.
- **Disposition: CORRECTED-GREEN, ~2s** (4 stable runs). Files edited: scenario `.js` + `attack_checks.go` (comment/spec-link only, no behavior change).

### ⚑ CROSS-CUTTING INFRA FIX (wave 1) — engine turn webhooks were unreachable
The hub defaults `UPSILON_WEBHOOK_URL` to `http://proxy:8085/api/webhook/upsilon` (a
docker-compose service name). On this native/bare-metal stack `proxy` does not resolve,
so the engine's `game.started`/`turn.started`/`board.updated` callbacks all failed
(`dial tcp: lookup proxy: no such host`) — **every turn-based battle scenario hung on the
first `waitNextTurn()` and timed out at 60s**. This blocked all three wave-1 agents from
obtaining a valid run. **Fix:** restarted the hub with
`UPSILON_WEBHOOK_URL=http://127.0.0.1:8090/api/webhook/upsilon`. After the fix,
`edge_movement_entity_collision` passes in 1s and `edge_movement_already_attacked` reaches
real game logic in 4s. (Wave-1 agents' static ATD/code analysis + test-link corrections
remain valid; only their run verdicts were re-done post-fix.)

### edge_movement_entity_collision — CORRECTED, GREEN (1s)
- C1 ✅ edge sits in `mech_move_validation` check #8 (Entity Collision → `entity.path.occupied`).
- C2 🔧 phantom `mech_move_validation_entity_collision` + tangential `entity_character` test-links → fixed to `mech_move_validation` + `mechanic_multi_entity_cell_system` (the atom the enforcing `move.go:162` block is spec-linked to). Production spec-link placement was already correct (dedicated block inside `preMoveChecks`).
- C3 ✅ near-simplest. C4 ✅ `move.go:163-167` rejects occupied dest via `HasBlockingEntity`. C5 ✅ single edge.
- **Disposition: CORRECTED** (test-links); passes 1s post infra-fix.

### edge_movement_already_attacked — real assertion mismatch, re-dispatched
- C1 ✅ maps to `mech_move_validation` rule 4 (Already Moved, `entity.movement.already`) + `mech_action_economy`.
- C2 🔧 fixed two phantom test-links (`mech_move_validation_already_moved`, `mech_action_economy_action_cost_rules`) → `mech_move_validation` + `mech_action_economy`.
- **C3/C4 ⚠️:** scenario approaches the enemy by moving (spends move credits), then attacks, then moves → engine rejects with `entity.movement.nocredits`, not the asserted `entity.movement.already`. The scenario never isolates the attack→move lock. Needs a redesign that attacks without first exhausting movement (or asserts on the actual post-attack lock behavior).
- **Disposition: CORRECTION-NEEDED** — re-dispatched with working env to redesign + prove.

### edge_movement_obstacle_collision — ATD fixed; C3 rewrite needed, re-dispatched
- C1 ✅ maps to `mech_move_validation` rule 7 (Obstacle Collision → `entity.path.obstacle`) + `mech_board_generation` + `entity_grid`.
- C2 🔧 fixed two phantom test-links (`mech_move_validation_obstacle_collision`, `mech_board_generation_terrain_obstacles`) → `mech_move_validation` + `mech_board_generation` (`entity_grid` was already real). Prod gap noted: `move.go:169-174` lacks `@spec-link [[mech_move_validation]]`.
- C4 ✅ `move.go:169-174` rejects non-Ground/Dirt cells with `entity.path.obstacle`; unit-covered by `TestRuleMoveFailObstacle`.
- **C3 ⚠️:** two `SKIP` branches log-and-PASS with no assertion (false greens); assertion accepts any `entity.path.*` rather than specifically `entity.path.obstacle`; `planTravelToward` last-step force-overwrite can break adjacency and yield a different rejection. **Needs rewrite:** obstacle adjacent to start → single-step move onto it → assert exactly `entity.path.obstacle`; convert SKIPs to hard failures.
- **Disposition: ATD_DEFECT (fixed) + CORRECTION-NEEDED (C3)** — re-dispatched with working env.

### edge_movement_obstacle_collision — REWRITE COMPLETE (wave 2, ISS-108 filed)
- Rewrite is provably correct: single-step onto an orthogonally-adjacent obstacle → strict `assertEquals(error_key, "entity.path.obstacle")` → position unchanged. Both false-green SKIPs converted to hard `assert(false)`. `planTravelToward` + force-overwrite removed.
- **Flaky ~20%:** board generation (`placeRandomObstacle`, uniform-random, no spawn awareness) does not guarantee an obstacle adjacent to spawn. Verified: 2 GREEN / 8 HARD-FAIL across 10 runs. When GREEN, asserts exactly `entity.path.obstacle`. **ISS-108** filed (Medium) — recommends a test-seam for deterministic board layout (refs ISS-087/ISS-082).
- **Disposition: CORRECTED-GREEN (flaky, blocked by ISS-108).**

### edge_movement_already_attacked — REDESIGN COMPLETE (wave 2)
- The original assertion (`entity.movement.already`) was **always correct**. The engine DOES lock movement after attack: `attack.go:113-115` sets `HasMoved=true`; `move.go:200-204` rejects with `entity.movement.already`.
- The bug was **isolation**: the scenario approached the foe by moving (spending credits), and `preMoveChecks` runs the credits gate (`entity.movement.nocredits`, `move.go:182`) **before** the `HasMoved` gate (`entity.movement.already`, `move.go:200`). So `nocredits` always fired first.
- Fix: probe only on a **fresh, full-credit turn** (`me.move == me.max_move`) when a foe is already adjacent. Attack (sets `HasMoved`, leaves credits untouched) → move → `entity.movement.already`. Discovered + fixed a move+pass race (one action per loop iteration).
- **Disposition: CORRECTED-GREEN, 2s.**

### edge_movement_grid_boundaries — AUDIT COMPLETE, GREEN (wave 3)
- C1 ✅ `mech_move_validation` + `entity_grid` both on-point (grid.go boundary-check doc is explicit). Note: `mech_move_validation`'s 9 enumerated checks never explicitly lists the grid-boundary/`entity.path.notfound` check even though it's real first-in-line code (`move.go:146-149`) — flagged, not corrected (shared atom, not scenario-specific).
- C2 ✅ both `@test-link`s resolve to real atoms; prod spec-links correctly placed (`move.go:109`, `grid.go:15`).
- C3 ✅ single negative-coordinate move, deterministic, no board-gen RNG dependency, strict `assertEquals`.
- C4 ✅ `move.go:146-149` rejects out-of-grid via `CellsForPositions`; verified live: `entity.path.notfound`, position unchanged.
- C5 ✅ one edge case. C6 — none needed, already matches corrected style.
- **Disposition: GREEN, 2s.** No files edited.

### edge_movement_jump_limitations — CORRECTED, SKIP by design, ISS-109 filed (wave 3)
- C1 ✅ `mech_move_validation` rule 9 (`entity.path.notvalid`) + `entity_grid` genuinely trace.
- C2 🔧 phantom `[[mech_move_validation_move_validation_jump_limitations]]` → fixed to `[[mech_move_validation]]`. Prod spec-link (`move.go:109`) already correct.
- **C3 ❌ structural, not flaky:** `1v1_PVE` arena (`bridge_start.go`) uses `Flat` gen with `Height` range (2,3), capping board Z-delta at ≤2 == default `JumpHeight`; the rejection condition (`|Δheight| > JumpHeight`) can never be true. 6/6 empirical runs SKIP. Unlike ISS-108 (~20% flaky), this is 0% reachable, permanently.
- **Secondary defect:** scenario's single-step (`i==0`) move would assert the wrong key (`entity.path.notadjacent`, not `notvalid`) even if a cliff existed — only `i>0` steps yield `notvalid` (`move.go:153-155`, confirmed against `TestRuleMoveFailNotAdjascentJumpHeight`).
- C4 ✅ production check itself is correct and unit-tested; E2E coverage is ~0. C5 ✅ one edge case.
- C6 🔧 rewrote misleading "Hill map rarely" comment/log to accurately document permanent unreachability + the i==0/i>0 nuance.
- **ISS-109 filed (Medium)** — recommends fixing the scenario's path length regardless of reachability, correcting the atom doc's rule-9 wording, and long-term giving `1v1_PVE` (or a test mode) a `Hill`-based or taller arena so the edge becomes reachable via the public API.
- **Disposition: CORRECTED, SKIP-by-design (blocked by ISS-109), 2s.**

### edge_movement_wrong_controller_with_2 — CORRECTED-GREEN (wave 3)
- C1 ✅ `mech_move_validation` check #3 (Controller Mismatch, `entity.controller.mismatch`) is a genuine, exact match.
- C2 🔧 dropped tangential `@test-link [[entity_player]]` (real atom, but about account identity/GDPR/registration, unrelated to battle controller ownership) → left `[[mech_move_validation]]` only. Prod spec-link already correct.
- C3 ✅ bot 1 waits its own turn, issues one move on bot 0's entity, single try/catch, exact key assertion — near-simplest; wait-for-own-turn is harmless and consistent with sibling `_with_2` scenarios, not worth rewriting away.
- C4 ✅ `move.go:120-123` (`CheckControllerForEntity`) rejects with exactly `entity.controller.mismatch`, checked before turn/path/credit checks.
- C5 ✅ one edge case, no dead branches/false-green skips. C6 🔧 see C2.
- **Disposition: CORRECTED-GREEN, 3s** (4 runs, stable).

### edge_char_reroll_post_match — CORRECTED, RED, ISS-113 filed (wave 4)
- C1 ✅ `us_character_reroll` genuinely traces (already lists this scenario in its own `test_links`, code_links point at `profile.go`/`pg_profile.go`); the edge (reroll during vs. after account "creation flow") is exactly what `mech_character_reroll`'s own Availability clause describes.
- C2 🔧 phantom `[[mech_character_reroll_limit]]` (confirmed via `atd trace`: "atom not found") → relinked to the real `[[mech_character_reroll]]`, the atom `reroll()` itself is spec-linked to. Also removed a duplicate consecutive `@spec-link [[upsilonbattle:mech_character_reroll]]` in `profile.go:77-78` and added an explicit NOTE above `reroll()` documenting the unenforced Availability clause + ISS-113.
- **C3/C4/C5 🔧 the scenario never tested reroll at all:** both the "before" and "after" calls used `character_rename` (a cosmetic name-change endpoint with zero reroll/post-match semantics) — confirmed via `endpoints.go` and `profile.go`, there is no such thing as a "reroll" effect from renaming. Worse, since `character_rename` has no restrictions of any kind, the post-match call always succeeded (`200 "Character renamed."`, confirmed live), which threw the scenario's own `assert(false, "ERROR: Post-match reroll was accepted!")` — but that assert lived inside the same enclosing `try/catch`, silently swallowing the failure and logging a false "✅ Post-match reroll properly rejected: undefined" (`e.message` is `undefined` on the raw thrown value). Same "assert-inside-its-own-catch" defect class as #19. Rewrote to call `character_reroll` correctly for both pre- and post-match, moved the pass/fail assertion outside the try/catch so it can't be re-swallowed, and dropped a dead reroll_count/total_wins log tail that asserted nothing.
- **C4 ❌ real production bug, not a test bug:** once wired to the real endpoint, the post-match reroll call succeeds every time (3/3 deterministic runs, ~3-4s each, no ISS-110 PVE-wipeout flake risk — the scenario only needs the match to *end*, win or lose, not survive to act). `reroll()` (`profile.go:79-105`) enforces ownership and the 3-attempt `reroll_count` cap only; it has no check for match participation at all, contradicting `mech_character_reroll.atom.md`'s own documented "Availability: only during creation flow" clause.
- **Disposition: CORRECTED, RED (blocked by ISS-113), ~3-4s** (3/3 deterministic fails post-fix, same failure reason each time — not flaky).
- **ISS-113 filed (Medium)** — `reroll()` has no post-match/creation-flow gate; since `Reroll()` also zeroes `spent_cp`, this doubles as a potential CP-refund/respec exploit (bounded by the existing 3-attempt lifetime cap). Recommends either enforcing the documented gate (e.g. via `total_wins+total_losses > 0`) or correcting the atom doc if the count cap was meant to be the only real constraint.

### edge_char_reroll_limit — CORRECTED-GREEN (wave 4)
- C1 🔧 both original links phantom (`mech_character_reroll_limit`, `us_character_reroll_reroll_counter` — neither resolves in ATD); `uc_player_registration` real but tangential (whole registration flow, not the reroll-limit rule). Relinked to `upsilonbattle:mech_character_reroll` (exact match: "a player may reroll at most 3 times... checked against the limit before each attempt") + `us_character_reroll` (business story, same "up to three times" rule). Tool note: `atd_trace` only returns real `code_links`/`test_links` for this atom when queried with the fully-qualified `upsilonbattle:` prefix — bare ID returns an empty-code warning regardless of active project.
- C2 🔧 same relink; `profile.go`'s `reroll()` spec-link was already deduped from a doubled consecutive line by the concurrent #21 sub-agent (who also filed ISS-113 for an unrelated, real gap — the atom's "creation-flow-only" availability clause is unenforced).
- **C3 🔧 real test bug, not just non-strict:** the "4th reroll should fail" block called `upsilon.assert(false, ...)` on unexpected success *inside* the same `try` its own `catch` handled — a regression allowing extra rerolls would have been silently swallowed and logged as a pass (same anti-pattern as #19). Rewrote with an outer `fourthRerollRejected` flag plus `assertResponse(e, 403, "Reroll limit reached.")`.
- C4 ✅ verified live: 4th reroll → `403 "-- DEBUG MODE -- Reroll limit reached."`, `reroll_count` stays 3; matches `profile.go:90-93`, unit-covered by `TestUserCannotRerollPastLimit`.
- C5 ✅ single edge case (3-attempt cap boundary); setup/verification steps are in service of that one edge.
- **Disposition: CORRECTED-GREEN, ~2s** (4/4 runs stable, real 403 rejection each time).

### edge_prog_attribute_cap — CORRECTED-GREEN (wave 4)
- C1 ✅ `rule_progression` genuinely traces (already lists this scenario in its own ATD `test_links`); CP-cap boundary is exactly the edge the atom defines.
- C2 🔧 dropped tangential `[[entity_character]]` (schema atom for the in-game battle entity's stat block — different domain from the persisted progression object; same drop pattern already established for this atom by scenario #12) → single `[[rule_progression]]`. Prod `upgrade()` already carries a correctly-placed `@spec-link [[shared:rule_progression]]` (`profile.go:123`) — no code change needed.
- **C3/C6 🔧 was a total false green, not just non-simple:** the scenario invented a fictional cap formula (`10 + total_wins` against summed raw `hp+attack+defense+move`) — the real rule is `spent_cp <= 100 + total_wins*10`, CP-priced per attribute (HP 1 CP/pt, Attack/Defense 5, Movement 30, etc). It also read a nonexistent field `char.move` (real field: `movement`), poisoning every downstream computation with `NaN`; the resulting "excess" upgrade request (`hp: NaN` or a large negative) was rejected for an unrelated reason (type/negative-value validation, not the cap), but the catch block never checked the error key/message so it logged PASSED regardless. The "valid upgrade" branch was dead code (`NaN < 10` always false). Also played a full unneeded PVE match (`joinWaitMatch`+`sleep(10000)`), adding latency and exposure to ISS-108/ISS-110 flakiness for no reason. Rewrote to hit the real boundary directly on a fresh character (`spent_cp=0`, `cap=100`): `+101` HP → strict `assertResponse(e, 400, "Upgrade failed: Total spent CP (101) exceeds the allowed cap (100 based on 0 wins).")`; `+100` HP → succeeds with `spent_cp===100` (inclusive-boundary confirmation, same sanity-tail pattern as #15).
- C4 ✅ `profile.go:147-154` enforces the cap correctly; verified live (curl log: exact 400 message on cap+1, exact 200/`spent_cp:100` on cap-exact) and cross-checked against `character_upgrade_test.go`'s existing fixtures (identical formula/message shape).
- C5 ✅ single edge case (CP-cap violation); boundary-success tail is a sanity confirmation, not a second unrelated case.
- **Disposition: CORRECTED-GREEN, 0s** (3/3 stable runs, deterministic — no match/RNG dependency, unlike the original). No production bug — code was already correct; bug was entirely in the test. Files touched: `upsiloncli/tests/scenarios/edge_prog_attribute_cap.js` only.

### edge_prog_movement_gate — CORRECTED-GREEN (wave 4)
- C1 ✅ `rule_progression` genuinely traces (already lists this scenario in its own ATD `test_links`); its "Unrestricted Spend" clause is exactly on-point — it names the very mechanic ("legacy once every 5 wins Movement gate is removed") the scenario is supposed to guard.
- C2 🔧 confirmed phantom `[[us_win_progression_movement_locked]]` (`atd trace` → atom not found). Dropped real-but-wrong-domain `[[us_win_progression]]` — 0 code_links per `atd_trace` (a frontend "post-win progression screen" UI story, not this backend endpoint; same "fails to name impacted files" bar used to drop #10's `domain_skill_system`). Kept single `[[rule_progression]]`, matching `profile.go`'s existing correct `@spec-link` placement (no prod change needed).
- **C3/C6 🔧 total false green, worse than #22:** the scenario tested a mechanic that no longer exists. `docs/rule_progression.atom.md` v2.1 and `upsilonbattle:mechanic_character_point_buy_system` both explicitly state the old "once every 5 wins" Movement restriction was deleted — Movement is unrestricted Class A spend, self-balanced purely by its 30 CP/point cost. At 0 wins the CP cap is 100, so `movement:1` (30 CP) legitimately succeeds — meaning the scenario's own `upsilon.assert(false, "...was accepted!")` fired and was caught by its *own* enclosing catch block, which logged it as "properly rejected" (identical swallow pattern to #19's `edge_auth_session_timeout`). Steps 3 (a fabricated `wins/5` formula, unused/dead) and 4 (an unasserted HP-upgrade tail, C5 violation) were also removed. Rewrote to the real edge: prove the removed gate stays removed — a 0-win character (below the old 5-win threshold) successfully buys +1 Movement, strict `assertEquals` on resulting `movement` and `spent_cp` (30 CP spent, per `rule_progression`'s Movement cost).
- C4 ✅ `profile.go:123-181` (`upgrade()`) enforces only the global CP cap, no win/level gate on any stat — verified live (curl log: `movement 3→4`, `spent_cp 0→30` at `total_wins:0`), matching the atom exactly. No production bug.
- C5 🔧 removed the dead unasserted HP-upgrade tail → one edge case (the movement-gate-removal regression guard).
- **Disposition: CORRECTED-GREEN, 0-1s** (5/5 stable runs, deterministic — no match/RNG dependency). No production bug — code and atom doc were already correct; bug was entirely in the test. Files touched: `upsiloncli/tests/scenarios/edge_prog_movement_gate.js` only.

### edge_prog_negative_value — CORRECTED-GREEN (wave 4)
- C1 ✅ `rule_progression`'s own logic text states the exact rule: "Non-Negativity: No attribute is allowed to have a negative value" — genuine, exact-match edge.
- C2 🔧 dropped tangential `[[entity_character]]` — its logic describes the in-game battle-entity stat block (HP consumable, Move, Position, "in game only"), not the persisted progression object `character_upgrade` operates on; same wrong-domain drop already established for this exact atom by #12/#22. `validateUpgrade` (the actual per-field `int|min:0` enforcement point in `profile.go:249`, distinct from `upgrade()`'s CP-cap check which already carries the header `@spec-link [[shared:rule_progression]]`) had zero spec-link → added.
- **C3/C5 🔧 not simple, not one edge:** file bundled 3 near-identical negative-value sub-cases (hp/attack/defense — same `validateUpgrade` code path, only the field name differs) plus an unrelated, unasserted "zero upgrade" branch (0 is non-negative — out of scope for "negative value," and its catch/log did nothing regardless of outcome — a dead check). Collapsed to the single sharpest case (`hp: -1`). Also every sub-case's catch only logged `e.message`, never checking status or which field actually failed — the assertion would have passed identically for the correct rejection or a coincidentally-thrown unrelated error, matching the "any thrown error passes" false-green shape flagged repeatedly this audit. Replaced with `assertResponse(e, 422, "Validation failed")` + exact `e.meta.errors["stats.hp"][0] === "The stats.hp field must be at least 0."` check.
- C4 ✅ verified live (4/4 runs): `POST .../upgrade {stats:{hp:"-1"}}` → exact `422`/`-- DEBUG MODE -- Validation failed`/`meta.errors["stats.hp"]`, stats unchanged after; matches `character_upgrade_test.go`'s `TestCharacterUpgradeValidatesStats` fixture exactly (same message, same dotted field key).
- Minor: also fixed a stale nonexistent-field log reference (`char.move` → real field `movement`) — cosmetic only (log line, not used in any assertion), same defect class as #22's `char.move` bug but harmless here since it was never fed into a computation.
- **Disposition: CORRECTED-GREEN, 0-1s** (4/4 stable runs, deterministic — no match/RNG dependency). No production bug — `validateUpgrade`'s non-negativity check was already correct; bug was entirely in the test (wrong-domain link, redundant sub-cases, dead zero-value branch, no status/message check). Files touched: `upsiloncli/tests/scenarios/edge_prog_negative_value.js`, `upsilonhub/internal/gateway/profile.go` (spec-link + comment only, no behavior change).

### edge_match_invalid_game_mode — CORRECTED-GREEN (Phase 5 kickoff)
- C1 🔧 `req_matchmaking_matchmaking_queue` confirmed phantom (`atd trace` → "atom not found"); real atom is `req_matchmaking` — exact match: "Exactly four queue options are offered... any other mode is rejected with a 4xx error," already lists `matchmaking.go` in `code_links`. `spec_match_format` real but wrong-domain (structural format/team composition, not mode-string validation); dropped. Kept `api_matchmaking` as secondary (documents the Join endpoint's mandatory `game_mode` enum; `join()` already carries the spec-link).
- C2 🔧 relinked header to `[[shared:req_matchmaking]]` + `[[upsilonapi:api_matchmaking]]`. `validateJoin()` (`matchmaking.go:153`, the real `slices.Contains(battle.GameModes, gameMode)` gate) had zero `@spec-link` → added.
- **C3/C5 🔧 real defects:** a `forEach` over 4 invalid-mode strings all hit the identical `slices.Contains` miss — pure enumeration, no differentiated path (same class as #18's collapse); reduced to one case (`1v3_PVP`). Dead `if (e.status_code)` check never fires (real field is `status`, same phantom-field class as #16/#17). File also bundled an unrelated queue-lifecycle case (valid join → leave → `idle` status), already covered by `e2e_matchmaking_pve_instant.js`/`e2e_matchmaking_pvp_queue_with_2.js` — removed. Manual `onTeardown` fully duplicated `bootstrapBot`'s automatic teardown — removed.
- C4 ✅ verified live: `422`, `meta.errors.game_mode: ["The selected game mode is invalid."]`, pre/post-fix identical. No behavior change needed.
- **Disposition: CORRECTED-GREEN, 0-3s** (4/4 runs, deterministic — rejection fires pre-queue, no ISS-108/ISS-110 exposure). No production bug. Files touched: scenario `.js` + `matchmaking.go` (spec-link only).

### edge_match_leave_not_queued — CORRECTED-GREEN (Phase 5)
- C1 ✅ `api_matchmaking` genuinely traces; "Endpoint 2: Leave Queue" (`{"status":"idle"}` steady state) — the not-queued edge is exactly the idempotency boundary. Note: `atd_trace` code_links list only a frontend Vue file, not `matchmaking.go` despite a real spec-link there — stale/incomplete index entry, not corrected here.
- C2 🔧 `[[usecase_api_flow_matchmaking]]` phantom (`atd trace` → not found); real sibling `us_api_flow_matchmaking` also wrong-domain (0 code/test links, generic legacy-Reverb login→join narrative, never mentions leave/cancel) — dropped both, kept single `[[api_matchmaking]]`. Prod `leave()` already correctly spec-linked, no change needed.
- **C3/C4 🔧 false-tolerant, not a false green:** try/catch treated success and thrown-error as equally acceptable — a real regression (leave starting to reject) would still log PASSED. Verified live: `PG.LeaveQueue` is an unconditional DELETE with no existence check, always returns plain `200`. Rewrote to a direct un-caught call so a future error is a genuine failure.
- C5 🔧 removed a bundled unrelated join-then-leave-while-queued case, already covered by `edge_match_queue_while_queued.js`.
- **Disposition: CORRECTED-GREEN, 2-3s** (3/3 stable runs, deterministic). No production bug. Files touched: scenario `.js` only.

### edge_match_queue_while_queued — CORRECTED-GREEN (Phase 5)
- C1 ✅ `upsilonapi:rule_matchmaking_single_queue` exact match, own logic text states clauses 1-3 verbatim as the edge under test; already lists this scenario in its own `test_links`. `api_matchmaking` also real, same membership.
- C2 🔧 dropped phantom `[[usecase_api_flow_matchmaking]]` (confirmed nonexistent). Relinked to qualified `[[upsilonapi:rule_matchmaking_single_queue]]`+`[[upsilonapi:api_matchmaking]]` (bare IDs under-report code/test links, same tooling quirk as #20). Prod `join()` already correctly spec-linked, no change needed.
- **C3/C6 🔧 real defects:** intended-failure `assert(false, ...)` lived inside its own `try`/`catch` — regression would've been silently swallowed (same anti-pattern as #19/#21/#23/#24). Rewrote with outer `rejected` flag. Dead `e.status_code` check (real field `e.status`) → strict `assertResponse(e, 409, "Conflict: You are already in a matchmaking queue.")`.
- C4 ✅ verified live: `409`, exact message, `matchmaking.go:59-61`. No behavior change.
- **C5 🔧** bundled leave→idle→rejoin tail (clause 4), already covered by `TestUserCanLeaveMatchmakingQueue` + `edge_match_leave_not_queued.js` — trimmed to one edge. Removed redundant manual teardown (bootstrapBot's automatic one already covers it).
- **Disposition: CORRECTED-GREEN, 1-3s** (4/4 runs). No production bug. Files touched: scenario `.js` only.

### edge_match_queue_while_in_match_with_2 — CORRECTED-GREEN (Phase 5)
- C1 ✅ `rule_matchmaking_single_queue` rule #2 (active-match join block) exactly on-point, distinct from #27's rule #1. Clean file — no phantom/wrong-domain links found.
- C2 🔧 `ErrInActiveMatch` (rule #2's error) had no spec-link, unlike sibling `ErrAlreadyQueued` which did → added, matching the established convention.
- C3/C5 🔧 bundled the named negative edge with an unrelated positive-path forfeit→requeue tail, which was also a benign but noisy 2-bot race (whichever bot forfeits first ends the match, the other's forfeit silently errors, never asserted). Trimmed to the 3 steps isolating rule #2. Removed redundant manual teardown (bootstrapBot's automatic one covers it).
- C4 ✅ verified live: `409` / `"Conflict: You are currently participating in an active match."` pre/post-fix.
- Not subject to ISS-108/ISS-110 — never plays a turn or touches board generation.
- **Disposition: CORRECTED-GREEN, 2-3s** (5/5 runs). No new defects.

### edge_equip_unowned_character — CORRECTED-GREEN (Phase 6)
- C1 ✅ `api_equipment_management`'s own logic names this exact edge (owner check runs before item resolution in `equip()`); genuinely undertested elsewhere (no Go unit test covers character ownership, only item ownership).
- C2 🔧 phantom `[[api_character_equip]]` (confirmed nonexistent) → `[[upsilonapi:api_equipment_management]]`, matching production's own header spec-link. No prod change needed.
- C3/C4 🔧 not a false green, but assertion was strictly broader than the real behavior: accepted `403 OR 404` when the code only ever returns `403`. Tightened to `assertResponse(e, 403, "This action is unauthorized.")`.
- C5 ✅ single edge case, no bundling.
- **Disposition: CORRECTED-GREEN, 1-4s** (3/3 post-fix + legit baseline pass). No production bug.

### edge_equip_wrong_slot — CORRECTED-GREEN (Phase 6)
- C1 🔧 `rule_equipment_slot_validation` confirmed phantom (self-referenced only). Real atom `upsilonapi:api_equipment_management` (code/test links confirmed).
- **C2/C3/C4 🔧 total false green, worse than #16/#19's swallow pattern:** zero API calls, zero assertions — pure narrated reasoning ending in an unconditional BYPASS pass. Investigation confirmed the scenario's own uncertainty was well-founded: `equip()` takes only `item_id`, slot is always server-inferred (DB CHECK constrained), atom explicitly forbids client-supplied slot — "wrong slot" is structurally impossible on the equip path. The only real wrong-slot validation is in `unequip()`: URL `{slot}` param checked against a fixed set, 422 `invalid_slot` for anything else (unit-tested, zero CLI coverage). Rewrote to `character_unequip` with `slot:"boots"` → strict `assertResponse(e, 422, "Unknown slot 'boots'.")`.
- C5 ✅ single edge case, distinct from #33 (valid-but-empty slot → 404, not invalid slot name → 422) — no overlap.
- Added missing 422/invalid_slot clause to `api_equipment_management.atom.md` (only 404/empty-slot branch was documented).
- **Disposition: CORRECTED-GREEN, 2-3s** (3/3 runs, deterministic). No production bug.

### edge_equip_unowned_item — CORRECTED-GREEN, ISS-114 filed (Phase 6)
- C1 ✅ `upsilonapi:api_equipment_management` (fully-qualified — bare ID under-reports) traces cleanly, logic explicitly documents "User owns the inventory row."
- C2 🔧 dropped phantom `[[api_character_equip]]` → `[[upsilonapi:api_equipment_management]]`. Prod already correctly spec-linked.
- C3 🔧 loose `403||404` hedge → strict `assertResponse(e, 403, "Inventory item does not belong to you.")` + `meta.reason==="inventory_not_owned"`, verified byte-for-byte against code + unit test.
- C4 ✅ verified live 6/6 runs. C5 ✅ single edge case.
- **Disposition: CORRECTED-GREEN, 1-2s** (6/6 runs, 0 flakes).
- **ISS-114 filed (Low)** — `Agent.GoTeardownHook` is a single-slot closure: a second `bootstrapBot` call in one scenario overwrites the first's teardown, so the surviving closure deletes whichever account is *currently authenticated* (mislabeled in its own log), permanently orphaning the other. Affects 3 files that double-`bootstrapBot`: `edge_equip_unowned_character.js` (#30), `edge_skill_unowned_character_equip.js` (#34), `edge_skill_unowned_character_roll.js` (#39). This scenario reverted to single-`bootstrapBot`+manual-register to avoid the bug rather than fix the harness (out of scope).

### edge_unequip_empty_slot — CORRECTED-GREEN (Phase 6)
- C1 ✅ confirms #32's distinction: `unequip()` has two failure modes on `{slot}` — invalid name → 422 (#32), valid-but-unoccupied → 404 `slot_empty` (this scenario, `character.ErrSlotEmpty`).
- C2 🔧 only defect: phantom self-referential `@test-link [[api_character_unequip]]` → `[[upsilonapi:api_equipment_management]]`. Atom doc already carries the correct 404 clause from #32's edit.
- C3 ✅ already simplest form (fresh character, no equipment row, direct call hits empty-slot 404).
- C4 ✅ verified live: exact `404 "Slot 'weapon' is empty."`, `meta.reason:"slot_empty"`.
- C5 ✅ single edge case, strict assertion already in place, no self-swallow risk.
- **Disposition: CORRECTED-GREEN, 2-3s** (5/5 runs). No production bug.
- **Tooling note:** `trigger_one_ci_test.sh` sometimes needs the full filename (`edge_unequip_empty_slot`), not just the prefix-stripped form — inconsistent across scenarios, worth a follow-up look.

### edge_movement_path_not_adjacent — AUDIT COMPLETE (wave 2)
- C2 🔧: header `@test-link [[mech_move_validation_path_adjacency]]` was a **phantom** → fixed to `[[mech_move_validation]]`.
- C5 🔧: removed superfluous valid-move tail (old lines 63-81, no assertions) → one edge per file; 83→63 lines.
- C4 ✅: `move.go:153-155, 194-197` emits exactly `entity.path.notadjacent`.
- **Doc typo (not a code bug):** the `mech_move_validation` atom spells the key `entity.path.notadjascent` (stray 's'); production code + test correctly use `entity.path.notadjacent`.
- **Disposition: CORRECTED-GREEN, 3s.**

### edge_match_forfeit_out_of_turn_with_2 — CORRECTED-GREEN (wave 5, resumed after abort)
- A prior session was aborted mid-work on this scenario, leaving an uncommitted draft in the working tree that was never run or logged. Re-verified from scratch rather than trusted.
- C1 ✅ `rule_forfeit_battle` + `uc_match_resolution` both real, both already list this scenario in their own `test_links`. Confirmed the draft's dropped `[[mech_initiative]]` was correctly identified as phantom-in-effect (real atom, 0% impl/test coverage, 0 code_links, wrong domain — turn-order/delay tickers, not forfeit).
- C2 ✅ `forfeit()` (`upsilonhub/internal/gateway/game.go:156-159`) already carries `@spec-link [[upsilonbattle:rule_forfeit_battle]]` with an explicit "no entity required" comment — no prod gap.
- C3/C4 ✅ verified in prod: `rules.Forfeit()` + `bridge_action.go:214` (`EntityID: uuid.Nil, // Forfeiting is team-wide`) confirm forfeit genuinely bypasses turn ownership, matching the rule.
- **C6 🔧 draft was directionally right but incomplete:** it fixed the turn-check (`current_player_is_self` instead of comparing a single owned entity ID) and made both bots pass-only so the 1v1_PVP match (full 3-character squads) stays alive long enough for bot 1 to see an opponent's-turn window — but a sampling-bias race remained: bot 0 reacts near-instantly via SSE while bot 1 only polled every 150ms, so bot 1 almost never actually landed inside the short window. Fixed: bot 1 polls at 50ms/400 attempts, bot 0's round cap raised (was exhausting first and exiting via the teardown-hook auto-forfeit from the wrong side), and bot 0's post-pass call wrapped in try/catch to tolerate the legitimate `arena.notfound` race once bot 1's forfeit lands.
- C5 ✅ single edge case.
- **ISS-102 does not apply** — confirmed empirically (11 runs): bot 1's forfeit lands ~50-300ms into an ongoing pass-loop, well past the engine's startup tick, not in ISS-102's ~2ms post-`match.found` window. Tracker's "ISS-102 candidate" tag dropped.
- **Disposition: CORRECTED-GREEN, 2-4s** (11/11 runs). No production bug — all defects were scenario-side timing/race issues. Files touched: scenario `.js` only.
- ⚠️ **Needs human review.** This scenario was also the one aborted mid-flight in the previous session, and its fix is a hand-tuned poll-rate/round-cap race resolution (50ms polling, 400 attempts, raised round caps) rather than a structural fix — worth a person's eyes to confirm the timing margins are comfortable under real CI load (not just this dev box) before fully trusting it long-term.

### edge_skill_equip_invalid_id — CORRECTED-GREEN (wave 5, resumed after abort)
- Also left as an uncommitted, unverified draft by the same aborted session. Independently re-verified rather than trusted.
- C1 ✅ `upsilonapi:api_character_skill_inventory` (qualified) traces cleanly, 100% impl/test coverage, already lists this scenario in `test_links`.
- C2 ✅ prod spec-link already correctly placed above `findSkill` (`skills.go:203-204`, the `findOrFail`-equivalent 404 path) — no prod change needed.
- C3/C4 ✅ well-formed but nonexistent UUID is the simplest way to hit this 404, distinct from #38's ownership-based 403. Verified live: `findSkill`→`GetSkill`→`pgx.ErrNoRows`→`ErrNotFound`→404, exact message `"No query results for model [App\Models\CharacterSkill] <uuid>"` reproduced including the `-- DEBUG MODE --` prefix.
- C5 ✅ single case, no bundling.
- C6 🔧 (inherited from draft, independently verified) fixed assert-inside-own-catch (same class as #16/#19/#21/#23/#24/#27); tightened to the exact 404 message.
- **Disposition: CORRECTED-GREEN, 1-3s** (5/5 runs). No production bug. Note: flagged a likely false-green in #38's assertion message ("unauthorized" guessed but not confirmed at the time) — resolved when #38 was audited (see below): the guess was wrong, but the assertion coincidentally passed anyway.

### edge_skill_slot_full — CORRECTED-GREEN (wave 5, resumed after abort)
- Also an uncommitted, unverified draft from the aborted session. Independently re-verified — draft required no further changes.
- C1 ✅ qualified `upsilonapi:api_character_skill_inventory` confirmed correct (bare form is a 0-coverage stub — same tooling quirk as #30-#35).
- C2 ✅ enforcement chain traced: `equipSkill` (`skills.go:136`, spec-linked) → `character.EquipSkill` (`pg_skills.go:68-82`, `len(equipped) >= slots` → `ErrSkillSlotFull`) → 422 `"All %d skill slot(s) are occupied."` + `meta.reason: "ERR_SKILL_SLOT_FULL"`. No gaps.
- C4 ✅ slot formula verified exact: `character.go:66-72`, `1 + wins/10` capped at 5 (Go truncating division) — matches draft's `min(5,1+wins/10)` claim precisely.
- C3/C5 ✅ single edge case (roll→equip→roll→equip-reject), near-simplest.
- C6 🔧 (inherited from draft) fixed assert-inside-own-catch; strict `assertResponse(e,422,"All 1 skill slot(s) are occupied.")` + explicit `meta.reason==="ERR_SKILL_SLOT_FULL"` check.
- **Disposition: CORRECTED-GREEN, 0-2s** (5/5 runs, deterministic). No production bug.

### edge_skill_template_not_found — CORRECTED-GREEN (wave 5)
- Fresh audit, untouched by any prior session.
- C1 🔧 confirmed the same bare-vs-qualified split as #30-#35: bare `api_skill_template_browse` → phantom stub (0 code/test links); qualified `upsilonapi:api_skill_template_browse` → real, 4 code_links/3 test_links, already lists this scenario. Fixed header.
- C2 🔧 `showTemplate` (`skills.go:53-65`) had zero `@spec-link`, unlike sibling `listTemplates` — added dedicated header tag.
- C3/C4 ✅ verified live (5/5): exact `404`/`"-- DEBUG MODE -- No query results for model [App\Models\SkillTemplate] <uuid>"`; confirmed the substring-match-under-DEBUG-prefix mechanism actually fires correctly here (not just assumed).
- C5 ✅ single edge case already.
- C6 🔧 fixed assert-inside-own-catch; empirically verified this instance wasn't silently swallowing a false-green (the panic path would have surfaced a confusing but real failure either way) — fixed for correctness/clarity per established convention regardless.
- **Disposition: CORRECTED-GREEN, ~2-3s** (5/5 runs). No production bug. Note: edited shared `skills.go` concurrently with sibling agents on #37/#38 — confirmed no overlap (each added a spec-link to a different function).

### edge_skill_unequip_not_equipped — CORRECTED-GREEN (wave 5)
- Fresh audit, untouched by any prior session.
- C1 🔧 same bare-vs-qualified fix as above; qualified form already lists this scenario in `test_links`.
- C2 🔧 `unequipSkill` (`skills.go:161-180`) had **zero** `@spec-link`, unlike siblings `equipSkill`/`findSkill`/`roll` — added dedicated header tag.
- C3/C4 ✅ already simplest edge (roll, don't equip, unequip → single case). Verified live: exact `422 "Skill is not currently equipped."` + `meta.reason: "ERR_SKILL_NOT_EQUIPPED"`. Notable nuance: `respond.ErrorMeta` (unlike `respond.ExceptionError`) does **not** add the `-- DEBUG MODE --` prefix, so this is the strict-match branch of `assertResponse`, not the debug-substring fallback — distinct from #34/#36's cooldown/template cases.
- C5 ✅ single case, no bundling.
- C6 🔧 fixed assert-inside-own-catch (same class as #16/#19/#21/#23/#24/#27/#36).
- **Disposition: CORRECTED-GREEN, 1-3s** (5/5 runs, deterministic). No production bug; no board-gen/turn logic, so no ISS-108/109/110 exposure.

### edge_skill_unowned_character_equip — CORRECTED-GREEN, ISS-114 reconfirmed (wave 5)
- Fresh audit, untouched by any prior session. Two flagged risks going in: a suspected false-green assertion message, and ISS-114 exposure (this file double-`bootstrapBot`s, explicitly named as affected).
- C1 🔧 same bare-vs-qualified fix. C2 🔧 `ownedCharacter` (`skills.go:186-200`, the actual character-ownership gate this scenario exercises) had zero `@spec-link` — added.
- **C3/C4 🔧 not a false green, but a coincidental pass:** `assertResponse(e,403,"unauthorized")` only passed because "unauthorized" substring-matches the real DEBUG-prefixed message. Traced the real path: `equipSkill`→`ownedCharacter` rejects on character ownership *before* skill resolution even runs, exact message `"This action is unauthorized."` (a sibling agent's guess of `"Skill does not belong to this character."` was real code, but belongs to `findSkill` — a different edge, #34's). Tightened to the exact string.
- **ISS-114 confirmed live via DB:** baseline (double-`bootstrapBot`) orphaned every `owner_eq_*` row across all 5 runs (`deleted_at` NULL) while `attacker_eq_*` correctly deleted — the second `bootstrapBot` call silently discarded the owner's teardown hook. Applied #31's precedent: attacker registers via plain `auth_register`/`auth_login` (no second `bootstrapBot`), script re-logs-in as owner before finishing so the sole surviving teardown hook targets the account it's labeled for. Verified post-fix: owner now deletes deterministically (attacker leaks instead — same accepted trade-off as #31).
- C5 ✅ single edge case, no bundling.
- **Disposition: CORRECTED-GREEN, 1-3s** (5/5 runs, deterministic pre- and post-fix). Files touched: scenario `.js` + `skills.go` (spec-link only).

### edge_skill_unowned_character_roll — CORRECTED-GREEN, ISS-114 reconfirmed (wave 5, closes Phase 6)
- Fresh audit; structurally near-identical to #38 (owner/attacker, ownership-gated action expects 403), both carried-over risks independently re-verified rather than assumed.
- C1 🔧 bare `api_character_skill_inventory` confirmed phantom stub → qualified `upsilonapi:api_character_skill_inventory` (100% coverage, already lists this file). `rule_character_skill_slots` genuinely traces either way but governs slot-capacity, not ownership — rejection here fires in `ownedCharacter()` before any slot logic runs, so dropped as tangential (same drop pattern as #8/#12/#22/#24).
- C2 ✅ no code change needed — `ownedCharacter()` (`skills.go:191`), the shared gate for roll/equip/unequip/list, already carries the right spec-link from #38's fix.
- **C3/C4 🔧 assertion only coincidentally passed, same class as #38/#34:** `roll()` calls `ownedCharacter()` first, rejecting via `forbidden(c)` → exactly `"This action is unauthorized."` (403) — same mechanism as the equip case since both share the gate. Old `assertResponse(e,403,"unauthorized")` only passed via substring match; tightened to the exact string, verified live.
- No assert-inside-own-catch anti-pattern — structurally safe (would panic rather than swallow).
- **ISS-114 confirmed live via DB, independently of #38:** baseline orphaned all 3 pre-fix `owner_*` rows. Applied #31/#38's precedent (plain `auth_register`/`auth_login` for attacker, re-login to owner before script end). Verified post-fix: 5/5 owner rows deleted deterministically.
- C5 ✅ single edge case, no bundling.
- **Disposition: CORRECTED-GREEN, 1-5s** (5/5 runs). Files touched: scenario `.js` only. **Phase 6 (Equipment/Skills, #30-39) now fully complete.**

### edge_shop_insufficient_credits — CORRECTED-GREEN (Phase 7 kickoff)
- C1 🔧 bare `api_shop_purchase` under-reports (missing this scenario's own test_link) vs qualified `upsilonapi:api_shop_purchase` (5 code_links incl. `shop.go`/`pg_inventory.go`, correctly lists this scenario). `rule_credit_spending_shop` is a **total phantom** (`atd trace` → not found, zero references anywhere but this file) — dropped, kept sole qualified link.
- C2 ✅ prod spec-links already correct on `purchase()`/`Purchase()` headers — no gap.
- C3 🔧 original spent down via 5 separate purchase calls (guessing 5×200=1000 starter credits) then a 6th — collapsed to one deterministic over-budget purchase (`quantity: 6` @ 200 = 1200 > 1000 starting balance), mirroring #22's CP-cap simplification. Verified live: starter credits = 1000, Basic Armor = 200 — comment's old guess was right but had never been verified.
- C4 🔧 tightened bare `e.status === 422` (no message/reason check) to exact `assertResponse(e,422,"Insufficient credits (1000 < 1200).")` + `assertEquals(e.meta.reason,"insufficient_credits")`; verified byte-for-byte against `pg_inventory.go:60-64`.
- C5 ✅ single edge case. Added a defensive null-guard + cost sanity-assert on the armor lookup (previously assumed blindly).
- **Note (not actioned):** live shop catalog has grown past the atom doc's documented "3-row V2.0 seed" — atom-doc staleness shared with #41/#42's domain, flagged not fixed (shared doc, concurrent sibling agents).
- **Disposition: CORRECTED-GREEN, 1-3s** (5/5 runs, deterministic). No production bug.

### edge_shop_unknown_item — CORRECTED-GREEN (Phase 7)
- C1 🔧 bare `api_shop_purchase` under-reports (impl 0.5, UI-only code_links, 1 playwright test) vs qualified form (impl 0.667, 5 code_links incl. Go, 6 test_links, lists this scenario) — fixed header.
- C2 ✅ prod already correctly spec-linked (`shop.go:46-51`) — no change needed.
- C3/C4 ✅ well-formed-nonexistent UUID is the simplest edge (item lookup is the first gate, before quantity/credits/cap checks). Confirmed the 404 uses a hand-written `respond.ErrorMeta` literal (`"Shop item not found."`), **not** the DEBUG-prefixed `ExceptionErrorMeta` path used elsewhere (#34/#36) — so the exact-string assertion was already correctly strict, not loose-by-luck. Verified live 5/5.
- C6 🔧 assert-inside-own-catch present but traced as non-swallowing (a regression would double-panic loudly, not silently pass) — fixed to the outer-flag convention anyway for consistency, matching #36's precedent.
- C5 ✅ single edge case.
- **Disposition: CORRECTED-GREEN, 1-3s** (5/5 runs). No production bug.

### edge_quantity_cap_99 — CORRECTED-GREEN (Phase 7)
- C1 🔧 `rule_quantity_cap` is a genuine, real atom (correct ancestry via `entity_player_inventory`/`mechanic_shop_inventory_system`) — notably **not** a phantom, breaking this audit's usual pattern. Bare form resolves to the same atom but under-reports tests; qualified `upsilonapi:rule_quantity_cap` is the form listing this scenario.
- C2 🔧 real gap: enforcing code (`pg_inventory.go:83`, `newQuantity > QuantityCap`) had **zero** `@spec-link` despite the atom being well-formed — added it. Also fixed the atom doc's stale `TECHNICAL INTERFACE` reference (pointed at a nonexistent PHP test name; corrected to the real Go test + this CLI scenario).
- **C3/C4 🔧 total false green, same class as #32:** zero API calls, zero assertions, hard-coded "let's just document it" BYPASS pass. The stated blocker (99×200=19,800 CR) was a red herring — the cap bounds total owned quantity, not purchase cost, so an admin-created 1-credit item (mirroring the Go unit test's own `createShopItem` technique) reaches 99 units for 99 CR total, well within the 1000 CR starting balance.
- C5 ✅ single edge case (99-succeeds boundary + 100-rejects + state-non-mutation check).
- **Disposition: CORRECTED-GREEN, 1-3s** (5/5 runs). Verified live: 99-unit purchase succeeds (1000→901 CR), 100th unit rejected exact `422 "Inventory quantity cap reached (100 > 99)."` + `meta.reason="quantity_cap"`, inventory stays at 99. No production bug — pure test/ATD-linkage defect. Phase 7 (Shop/Economy) now fully complete.

### edge_api_missing_request_id — CORRECTED (harness-layer only), ISS-115 filed (Phase 8 kickoff)
- C1 ✅ all three original links genuinely real (unusual for this audit — not phantom). Real requirement: server falls through body→header→fresh-UUIDv7, **never rejects** a missing/malformed id (`respond.go:RequestID`, lines 138-160); confirmed live via raw curl bypassing the CLI (no-header+no-body → 200 with generated id; malformed header → 200, echoed verbatim, no format check).
- C2 🔧 relinked header to qualified `upsilonapi:api_request_id`/`upsilonapi:api_standard_envelope` (bare under-reports, missing code carrying the qualified tag — same tooling quirk as #30-39); prod already correctly spec-linked, no code change needed.
- **C3/C4 🔧 total false green by scope-mismatch:** file made zero assertions about request-ID behavior, just logged PASSED regardless, per its own admitted "documentation marker" framing. **Structurally unreachable, confirmed deterministic (5/5 runs):** `upsiloncli/internal/api/client.go:Client.Do` unconditionally injects a fresh UUIDv7 into both the body's `request_id` and the `X-Request-ID` header on every call — no raw-HTTP escape hatch exists in the bridge. Same conclusion pattern as #17 but **distinct root cause from ISS-112** (transport-client injection, not the admin-route guard) — new issue filed rather than reused.
- C5 ✅ single edge case after rewrite. C6 🔧 rewrote to pin the one observable thing: the CLI's own generated `request_id` round-trips unchanged through the error envelope (bogus-UUID lookup → 404), honest header comment citing the curl evidence.
- **Disposition: CORRECTED (harness-layer only), GREEN, 1-3s** (5/5 runs). No production bug — the real fallback is already Go-unit-tested (`respond_test.go:TestGeneratesFreshUUID7IfMissing`).
- **ISS-115 filed (Low)** — CLI transport client cannot omit/spoof the request-id header/field; recommends a future `upsilon.rawCall(...)` escape hatch if genuine E2E coverage is ever wanted.

### edge_api_invalid_uuid — CORRECTED-GREEN (Phase 8)
- C1 🔧 dropped both original links: `entity_character` confirmed tangential (battle-entity schema, same wrong-domain pattern as #12/#22/#24/#39); `api_standard_envelope` over-broad. Relinked to `upsilonapi:api_profile_character` (qualified — bare under-reports), which already names `characterId` as the mandatory UUID input.
- C2 🔧 `findCharacter` (`profile.go:232`, the actual `uuid.Parse` gate) had zero dedicated spec-link — added one; also added a missing EXPECTATION clause to the atom doc for the real (undocumented) 500 behavior.
- **C3/C4 🔧 real defect was in the test's status-class assumption, not just enumeration:** `findCharacter` has no format pre-check — `uuid.Parse` failure panics via `must(err)`, caught by `Recovery()`, rendered as a deliberate **500** (byte-parity with legacy PHP's `QueryException`, documented in-code as intentional). The old dead `if (e.status_code)` check (real field is `e.status`, same phantom-field class as #16/#17/#25) meant nothing was ever actually asserted, and it was asserting the wrong status class (4xx) besides.
- **C5 🔧** 7-value enumeration collapsed to one sharpest case (`"not-a-uuid"`); dropped the `""` case (hits an unrelated routing/404 path, not UUID-parsing); kept the closing valid-UUID sanity check.
- C6 🔧 fixed assert-inside-own-catch (same anti-pattern class); removed a redundant manual `onTeardown` (bootstrapBot's automatic one already covers it, same pattern as #26/#27/#28).
- **Disposition: CORRECTED-GREEN, 1-3s** (5/5 runs). No production bug — the 500 is deliberate documented byte-parity, not a regression.

### edge_api_malformed_json — CORRECTED-GREEN, full rewrite (Phase 8)
- Confirmed the file's own premise empirically: the CLI bridge always emits well-formed JSON (string params pass through, everything else `json.Marshal`'d) — no seam exists to inject broken JSON syntax, same conclusion class as #17/#43's honest reframes, verified rather than trusted.
- **Confirmed a real JS bug live:** the "invalid HP type" block referenced `validCharId`, declared later inside an `if` block (TDZ) — a `ReferenceError` at runtime, silently swallowed by that block's own bare `catch(e){log}`. That sub-case never tested anything, ever.
- C1/C2 🔧 dropped both original links (`api_standard_envelope`, `api_laravel_gateway` — real but wrong-domain, neither addresses parameter-type validation) → relinked to `shared:rule_progression`, matching `validateUpgrade`'s existing correct prod spec-link. No code change needed.
- **C3/C5 🔧 total rewrite:** collapsed 3 bundled sub-cases + weak valid-request tail to one sharpest edge: `character_upgrade` with `hp: "not-a-number"` — hits `validateUpgrade`'s `!isInt` branch before any character lookup/CP-cap math runs. Confirmed distinct from `edge_prog_negative_value` (same function, `min:0` branch), `edge_prog_attribute_cap` (CP-cap branch), and `edge_api_invalid_uuid` (path-param `uuid.Parse` panic, structurally can't reach this 422 branch) — no duplication. "Missing characterId" was investigated and rejected as an alternative edge (short-circuits into #44's existing empty-UUID 500 path instead).
- C4 ✅ verified live 5/5: exact `422`/`meta.errors["stats.hp"] = ["The stats.hp field must be an integer."]`, stats unchanged.
- **Disposition: CORRECTED-GREEN, 0-1s** (5/5 runs). No production bug. Files touched: scenario `.js` only.

### edge_api_5xx_error_handling — CORRECTED (harness-layer reframe) (Phase 8 close)
- C1 🔧 dropped phantom-domain `[[mechanic_frontend_auth_bridge]]` (0 code/test links, SPA-only bridge, same wrong-domain conclusion already reached for #16/#43); relinked to qualified `[[upsilonapi:api_standard_envelope]]` (bare under-reports; qualified form already lists this file and #43's in its own `test_links`).
- C2 ✅ prod (`respond.go`/`errors.go`) already correctly spec-linked, no change needed.
- **C3/C4 🔧 confirmed no genuinely new 5xx trigger exists:** repo-wide grep for the `uuid.Parse`→`must(err)`→panic→`Recovery()`→500 pattern found it repeated at 9 call sites across `profile.go`/`admin_content.go`/`game.go`/`shop.go`/`equipment.go`/`skills.go` — all the *same mechanism* #44 already established and strictly asserts. Reusing a sibling endpoint would only duplicate #44's mechanism on a different route, not surface a distinct 5xx class — declined.
- Original was a total scope-mismatch false green (own comment admitted it "can't easily trigger 5xx," then substituted an unasserted 4xx block of soft `if (e.field) log(...)` duck-typing that would pass even if every field were silently dropped).
- C6 🔧 reframed honestly (same pattern as #43): strict assertions on a real, reachable 401 (`success===false`, exact `assertResponse(401,"Invalid credentials.")`, non-empty `request_id`/`message`, explicit assert of `error_key` absence for this error class — confirmed live that plain credential rejections never set one, unlike engine rule-rejections).
- C5 🔧 dropped an unrelated trailing "successful response" duck-typed tail — one edge per file.
- **Disposition: CORRECTED (harness-layer), GREEN, 0s** (5/5 runs, deterministic). No production bug, no issue filed (already-covered hard-to-trigger error class, not a specific untested code path). Files touched: scenario `.js` only. **Phase 8 (API/Envelope, #43-46) now fully complete.**

### edge_leaderboard_invalid_mode — CORRECTED-GREEN (Phase 9 kickoff)
- C1 ✅ bare `api_leaderboard` under-reports (0 code/test links); qualified `upsilonapi:api_leaderboard` real (`leaderboard.go`, already lists this scenario). Phantom `[[us_leaderboard_view_sort_leaderboard]]` confirmed via `atd trace` → not found, dropped.
- C2 🔧 header relinked to qualified form; `validateLeaderboard()` (`leaderboard.go:194`, the real mode-enum gate) had zero dedicated spec-link (only inherited `index()`'s header tag) → added, matching `validateJoin`/`findSkill`/`ownedCharacter` convention.
- **C3/C5 🔧** `forEach` over 6 invalid-mode strings, all hitting the identical validation-miss branch — pure enumeration, same class as #18/#25. Collapsed to one case (`3v3_PVP`). Dropped unrelated "valid modes" tail (already covered by `e2e_leaderboard_viewing.js`).
- Dead `if (e.status_code)` (phantom field, real is `e.status`) never fired → strict `assertResponse(e, 422, "Validation failed")` + exact `meta.errors.mode` check, mirroring `edge_match_invalid_game_mode`'s Phase-5 fix.
- C4 ✅ verified live: `422`, `-- DEBUG MODE -- Validation failed`, `meta.errors.mode: ["The selected mode is invalid."]`.
- **Disposition: CORRECTED-GREEN, 1-2s** (5/5 runs). No production bug — pure test/ATD-linkage cleanup, same class as #30-39/#43-46.

### edge_leaderboard_over_pagination — CORRECTED-GREEN (Phase 9)
- C1 ✅ same bare-vs-qualified fix as #47; same phantom `us_leaderboard_view_sort_leaderboard` dropped.
- C2 🔧 header only — `leaderboard.go:83-85`/`:225` already correctly spec-linked in prod, no code change.
- **C3/C4 🔧 false-tolerant catch-all, not a false green:** read `leaderboard.go:144-149` directly — `page=9999` can never error or 404; it always returns `200`/`success:true`/`results:[]` with correct `meta` (page pagination clamps via `start < len(ranked)` guard, never panics on out-of-range slices). The original try/catch's 404-acceptance branch and `e.status_code` check were both structurally dead. Verified live: `mode=1v1_PVP&page=9999` → `200`, `data.results:[]`, `meta:{current_page:9999,...}`.
- C6 🔧 removed the dead try/catch entirely; unconditional `assertEquals(results.length, 0)` + new strict checks that `meta.current_page` echoes the requested page and `meta.total`/`meta.last_page` stay consistent between page-1 and page-9999 calls (proves metadata isn't corrupted by an out-of-range request).
- C5 ✅ unchanged, one edge case; kept page-1 baseline as a sanity check.
- **Disposition: CORRECTED-GREEN, 0-3s** (6/6 runs). No production bug — pagination was already correct, just never actually verified. **Phase 9 (Leaderboard, #47-48) now fully complete.**

### edge_admin_anonymize_nonexistent — CORRECTED-GREEN (Phase 10 kickoff)
- C1 🔧 bare `uc_admin_user_management` phantom-stub (0 coverage) → qualified `upsilonapi:uc_admin_user_management` real (`admin.go`, `pg_admin.go`; already lists this file, #51, #49 in its own `test_links`).
- **C2/C3/C4 🔧 total scope-mismatch false green:** baseline (live-verified, 3s, PASSED) never touched anonymization — called `admin_users` as non-admin (blocked client-side by `bridge.go:110`'s hard guard, same ISS-112 mechanism as #17/#43/#49) then fell back to an unrelated `profile_character` all-zero-UUID 404 check. Rewritten using the `adminSection`/`admin.assertResponse` pattern already proven correct by #52: admin logs in, calls `admin_user_anonymize` with a garbage `account_name`, strict `404` + exact `"No query results for model [App\Models\User] <name>"` (verified live, DEBUG-prefix handled same as #34/#36/#52).
- Dropped `[[rule_gdpr_compliance]]` — 0 code_links/test_links in `atd trace` (doc-only), and the 404 fires in `findUser` before `AnonymizeAccount` is ever reached, so no anonymization-specific rule is actually exercised here (contrast with #51, where the atom's own `test_links` do list that file).
- C5 🔧 dropped the unrelated non-admin probe + `profile_character` tail — one edge remains (anonymize-nonexistent-user 404). No `bootstrapBot` needed (admin-only), sidesteps ISS-114 entirely.
- **Disposition: CORRECTED-GREEN, 0-1s** (5/5 runs). No production bug — `admin.go`'s `anonymize()`/`findUser()` already correct. **Scope note: this and #51 audit the admin-positive path (admin correctly rejects a bad target), not #49's non-admin-rejection path — not the same issue as ISS-112/ISS-103.**

### edge_admin_delete_nonexistent — CORRECTED-GREEN (Phase 10)
- C1 🔧 same bare-vs-qualified fix as #50; qualified `upsilonapi:uc_admin_user_management` confirmed real.
- **C2/C3/C4 🔧 same false-green class as #50:** baseline never touched `admin_user_delete`, same non-admin `admin_users` probe (harness-blocked) + unrelated `profile_character` tail. Rewritten via `adminSection`+`admin_user_delete` on a garbage `account_name` → strict `404` + exact `"No query results for model [App\Models\User] <name>"` (verified live).
- **`rule_gdpr_compliance` kept (unlike #50's drop):** `atd trace upsilonapi:rule_gdpr_compliance` shows real coverage (`auth.go`, `pg.go` code_links) and its `test_links` **already lists this exact file** (not #50's) — the atom index itself empirically distinguishes the two, and the atom's own text ("deletion MUST be a soft delete") is genuinely on-point for delete specifically.
- C2 🔧 real prod gap found: `destroy()` (`admin.go:93-96`) had **no `@spec-link` at all**, unlike sibling `anonymize()` (tagged). Added `@spec-link [[upsilonapi:uc_admin_user_management]]` above `destroy()`, matching `anonymize()`'s placement; comment-only, `go build` verified clean.
- C5 🔧 same trims as #50. C6 🔧 full rewrite.
- **Disposition: CORRECTED-GREEN, 0-1s** (8/8 runs). No production bug — `destroy()`/`findUser()` already correct byte-parity with legacy PHP.

### edge_admin_skill_template_not_found — CORRECTED-GREEN (Phase 10 close)
- Already the best-formed file in Phase 10 going in — used as the reference pattern #50/#51 copied. Audited properly rather than rubber-stamped; found two genuine, narrow defects.
- C1 🔧 same recurring bare-vs-qualified pattern (~12th occurrence this audit): bare `api_skill_template_admin_crud` phantom-stub → qualified `upsilonapi:api_skill_template_admin_crud` real (3 code_links, 6 test_links, already lists this file).
- **C2 🔧 real, spreading defect:** `@spec-link [[mechanic_script_admin_section]]` sitting inside this *test* file (above the `adminSection` call) violated the codebase's own test-vs-implementation tagging convention (`.agent/rules/ATD.md`: test files carry `@test-link` only). Root cause: `jsAdminSection` (`upsiloncli/internal/script/bridge_battle.go:602`, the actual implementation) had **zero** spec-link anywhere — `atd trace mechanic_script_admin_section` showed "has no linked code". Fixed at the source: added the spec-link to `jsAdminSection` itself (now covers all 8+ files that reference this atom via one prod fix, confirmed via `atd_check` — 12 impl links now resolve), removed the misplaced copy from this scenario. **Same misplaced tag confirmed still present in #50 and #51** (copy-pasted from this file before those were corrected) — one-line removal applied to both directly by the orchestrator post-landing, no new investigation needed.
- C3/C4 ✅ verified live (8+ runs): GET/PUT/DELETE all hit the same `findSkillTemplate` guard in `admin_content.go` first, byte-identical `404` output.
- **C5 🔧 judgment call:** collapsed the file's 3 verb sub-cases (GET/PUT/DELETE) to 1 (GET only) — all three share the identical guard clause and produced byte-identical assertions as written; PUT does have a theoretically distinct validation-precedence branch (422-before-404) but the scenario never exercised it, so as-written all three still collapse to one edge. Matches this audit's dominant enumeration-collapse precedent (#18/#25/#40/#42/#47) and the pattern #50/#51 (modeled on this file) already established independently. PUT's validation-precedence interaction flagged as a distinct, currently-uncovered edge for a possible future scenario — not actioned.
- **Disposition: CORRECTED-GREEN, 0-1s** (8+ runs, deterministic). No production bug — only doc/link/scope hygiene. **Phase 10 (Admin, #49-52) now fully complete.**

### edge_admin_private_data_access — CORRECTED, RED, ISS-116 filed, corrects the tracker's own "ISS-103 candidate" tag (Phase 10 close)
- The tracker's own handoff note had flagged this as an "ISS-103 candidate," hypothesizing it shared ISS-112's harness-can't-reach-admin-negative-path root cause. **Both halves of that hypothesis were checked, and both were wrong in different ways** — worth recording precisely since this corrects the tracker's own prior guidance rather than confirming it.
- C1/C2 🔧 three original links, two dropped: `[[uc_admin_user_management]]` (qualified — real, well-linked, even lists this file in its own `test_links` — but its documented scope is soft-deletion, not field censorship, so tangential despite the index metadata); `[[rule_gdpr_compliance]]` (0 code_links/test_links, doc-only). Kept `[[rule_admin_access_restriction]]`, qualified — its real logic ("admins MUST NOT see `full_address`/`birth_date`") is exactly this scenario's namesake edge. **ATD-doc/enforcement mismatch confirmed, not fixed (flagged only, per instructions on shared-doc caution):** the one prod code path spec-linked to this atom, `RequireAdmin()` (`middleware/auth.go:90`), enforces a *completely different* rule (route-level auth gate, who may call `/admin/*` at all) — it has zero connection to field-level censorship. No atom currently documents the route-authorization rule itself; no code currently implements the censorship rule this atom actually describes.
- **C3/C5 🔧** original file bundled three unrelated things: a non-admin-rejection attempt (confirmed structurally harness-blocked — `bridge.go:109-111` hard-blocks `admin_`-prefixed routes outside `adminSection()`, same mechanism as ISS-112/#17/#43), a dead `e.status_code` check (phantom field, same class as ~6 other scenarios), and an unrelated owner-self-visibility check that tested neither half of the atom. Rewrote to the one edge that's both the atom's real content *and* actually reachable: register a user with known private fields → `adminSection()` → `admin_users` listing → assert the fields come back censored.
- **C4 ❌ real production bug, not a test bug:** live-verified via raw curl (bypassing the CLI) and 3 CLI runs — `newUserJSON` (`resources.go:55-73`) is a single context-blind serializer reused for self-profile, login, *and* admin listing/anonymize responses; it never censors anything. A freshly registered user's raw `full_address`/`birth_date` come back verbatim to an admin caller via `GET /api/v1/admin/users`. **ISS-116 filed (Medium)** — distinct from both ISS-112 (CLI harness routing block — unrelated mechanism) and ISS-103 (a real, pre-existing, unrelated issue: foe-loadout masking in battle board state, different component and atom family entirely — the tracker's "ISS-103 candidate" tag was a reasonable a-priori guess but empirically wrong; cite ISS-112 for the non-admin-rejection half and ISS-116 for the censorship half going forward, not ISS-103).
- C6 🔧 full rewrite; per this audit's `edge_char_reroll_post_match`/ISS-113 precedent, left the assertion strict/RED rather than softened to a false green — the edge-case suite is reporting-only during this audit (see `ci_edge_case_reporting.md`'s own CI-gating note), so an honest red is preferred.
- **Disposition: CORRECTED, RED (blocked by ISS-116), <1s** (3/3 deterministic fails, same reason each time — not flaky). No production/atom-doc changes made (flagged the mismatch, didn't fix it, per shared-doc caution). Files touched: scenario `.js` + new `issues/ISS-116_*.md`.

### ⚑ CROSS-CUTTING (Phase 11 kickoff) — the entire "WebSocket" premise behind #53-55 no longer exists
`upsiloncli/internal/ws/listener.go`'s own package doc states it plainly: the CLI *"historically spoke the Pusher/Reverb websocket protocol; since the hub migration it consumes the hub's Server-Sent Events stream (GET /api/v1/events)... there are no channel subscriptions and no broadcasting/auth handshake anymore."* This was a deliberate prior platform migration (WS/Reverb → SSE), and the ATD atom docs are **already current** — `atd trace api_websocket`'s own logic text says outright: *"the connection itself is the user's private channel — there is no channel-auth handshake and no per-user channel key."* Only the three `edge_ws_*` scenario files are stuck describing the retired protocol (channel subscriptions, WS-level ping/pong frames) — none of that vocabulary maps onto anything reachable anymore. Notably the atom index's own `test_links` already point past the files' literal names: `upsilonapi:api_websocket_arena_updates` (replay/masking, the participant-authorization check in `events.go`'s `replayFrame`) lists `edge_ws_wrong_channel.js` in its own `test_links`, and `req_logging_traceability` (async webhook request-id propagation, not ping/pong at all) lists `edge_ws_ping_timeout.js` — suggesting these files' *intended* real edges were already anticipated by whoever wired up the ATD index, even though the file contents never caught up. Server-side ground truth: `/api/v1/events` requires standard `RequireAuth()` (router.go:172, same middleware as every other endpoint); heartbeat comments (`: hb\n\n`) fire every 25s (`events.go`, `defaultHeartbeat`); replay authorization for a stale `Last-Event-ID` requires match participancy (`events.go:114-116`, `!participant` → silently no replay, not an error). Sub-agents auditing #53-55 were briefed on all of this and instructed to pivot to the real reachable edges rather than force-fit the retired WS vocabulary.

### edge_ws_connection_no_token — CORRECTED-GREEN (Phase 11)
- C1 🔧 `[[api_websocket]]` (bare) confirmed real, matches its own SSE-documenting logic text. `[[req_security_authorization]]` confirmed phantom (same as #45's finding) → `[[req_security]]`, matching #16/#19's precedent.
- C2 🔧 `Listener.Sync()` (`upsiloncli/internal/ws/listener.go`, the actual no-token short-circuit: `if l.Session.Token() == "" { l.Stop(); return }`) had zero spec-link → added `[[api_websocket]]`.
- **C3/C4 🔧 baseline was a false green, same self-swallow class as #19/#21/#23/#24/#27:** `bootstrapBot` auto-caches a token before the "no-token" check ran, and the no-op `setContext("test_no_token", true)` flag (grepped, never read anywhere) meant `profile_get` succeeded with the real token — the scenario's own `assert(false, ...)` fired and was swallowed by its own enclosing catch, logging a false "properly rejected". Also confirmed the `help_endpoint` call dead-throws (`/help` route retired in the Phase 6 cutover, per #16).
- **C6 🔧 rewrite pivots to the SSE-era equivalent**, distinct from #16: `Listener.Sync()`'s own client-side connection guard, exercised via the harness's `wsConnect()`/`wsStatus()` primitives — fresh unauthenticated agent calls `wsConnect()`, asserts `wsStatus().connected === false`. Verified via code trace (not live fault-injection — the harness's own security classifier correctly refused a proposed live mutation-based negative test, request was reverted) that the assertion is robust to either enforcement layer alone failing: `streamOnce()` has its own independent token check, and server-side `bearerToken()` rejects empty/malformed bearers with a genuine 401 regardless.
- C5 🔧 collapsed 4 bundled sub-checks (register, no-op no-token call, dead `help_endpoint` call, redundant valid-token tail) to one edge.
- **Judgment call flagged by the sub-agent:** this scenario is adjacent to but not fully redundant with #16 — both root in `req_security`, but this one exercises the CLI-side `Listener.Sync()` code path specifically (distinct from `auth.go`/`profile.go`), a narrower distinction in the same spirit as #32/#33's kept-separate call.
- **Disposition: CORRECTED-GREEN, 0-1s** (10/10 runs, deterministic, zero HTTP requests even attempted — confirms the client-side short-circuit fires before any network call). No production bug — both guard layers were already correct.

### edge_ws_wrong_channel — CORRECTED-GREEN (Phase 11)
- C1 🔧 same bare-vs-qualified pattern as ~12 prior scenarios: bare `api_websocket`/`api_websocket_arena_updates` both phantom-stubs (0 test_coverage/0 code_links); qualified forms real, and `upsilonapi:api_websocket_arena_updates`'s own `test_links` already lists this exact file — confirming the atom index anticipated this file's real intended coverage before the file content caught up.
- **The pivot:** old Pusher/Reverb channel-subscription model is retired (connection itself is the private channel); the modern analogue of "wrong channel" is a forged `Last-Event-ID` for a match the caller isn't a participant in, gated by `s.battle.IsParticipant(...)` (`events.go:114-116`).
- **C4 verified live via raw curl, no production bug — a correctly-enforced security property:** two throwaway accounts, bot A (real participant) reconnects with `Last-Event-ID: {match_id}:0` → full replayed board frame; bot B (never a participant) sends the *same forged* id with B's own token → response is byte-identical (`: connected\n\n`, 13 bytes) to no-header-at-all or a garbage id. No leak.
- **Harness-layer ceiling confirmed, 3rd instance this audit (1st in Phase 11):** `bridge_ws.go`'s `wsConnect/wsDisconnect/wsStatus/wsSubscribe` can't forge `Last-Event-ID` (the `Listener` only ever populates it from real received frame ids); `/api/v1/events` isn't a registered `jsCall` route, no raw-HTTP escape hatch exists (same class as ISS-115/#43/#49, and independently reached by the sibling #53 agent for a different WS-layer edge — now a recognized Phase 11-specific pattern).
- C6 🔧 file now drives the legitimate half of the same mechanism entirely inside the harness (join match → poll for a real replay cursor → force disconnect/reconnect → confirm the listener resumes its own match's stream deterministically), with the raw-curl cross-participant denial proof recorded as verified evidence in the header comment (same framing precedent as #43).
- C5 ✅ surgical privacy masking (the atom's other clause) already has dedicated coverage in `e2e_battle_starts_privacy_check.js` — correctly left out, not duplicated. Dropped dead `ws_channel_key` field (column dropped in migration `000002_drop_ws_channel_key`; the old check was a no-op `if`, confirmed via baseline run it never asserted anything).
- **Disposition: CORRECTED-GREEN, 1-3s** (7/7 runs, deterministic). No production bug.

### edge_ws_ping_timeout — CORRECTED-GREEN (Phase 11 close, audit complete)
- Investigated both candidate SSE-era analogues per the cross-cutting brief:
  1. **Literal heartbeat survival** (`": hb\n\n"`, 25s cadence) — traced `SSEHeartbeat`'s override path end-to-end: wired into `sseAPI` but **never set anywhere in `cmd/upsilonhub/main.go`'s `gateway.Deps{}`** — only ever overridden in a Go unit test. The running hub this suite drives has no test-time knob, so waiting out even one real 25s heartbeat was judged impractical for this suite's runtime budget (old file was already an 11s, harness-flagged-slow scenario without even reaching one heartbeat). Documented as impractical rather than force-tested — same honesty-over-forced-coverage precedent as ISS-109 (#7).
  2. **Fresh `request_id` per async broadcast — the sharper, reachable edge, chosen as primary.** `req_logging_traceability` already lists this exact file in its own `test_links`; its dependent `rule_tracing_logging` states async webhooks/broadcasts must mint a fresh UUIDv7, not continue the triggering request's. Confirmed server-side: `sse.BoardFrame`/`sse.MatchFoundFrame` (`upsilonhub/internal/gateway/sse/sse.go`) each independently call `respond.NewID()`. Confirmed CLI-side: `Listener.dispatch()` forwards the full raw envelope to `notifyWaiters`, so `upsilon.waitForEvent(...)` genuinely exposes `request_id` to JS (unlike `upsilon.call()`'s success path, which only returns `.data` — a harness-layer ceiling noted but not blocking, same class as #43/#49).
- C1 ✅ kept both existing links (`api_websocket`, `req_logging_traceability`), retargeted content to what they actually describe.
- **C2 🔧 real doc gap:** `sse.BoardFrame`/`sse.MatchFoundFrame`, the literal enforcement points of "fresh request_id per broadcast," had zero spec-link despite the atom describing exactly this behavior → added `@spec-link [[req_logging_traceability]]` to both; `atd trace` confirms code_files 1→2, `go build` clean.
- **C3/C5 🔧** one sharp edge: two independently-broadcast SSE events (`game.started`, `turn.started`) must each carry a valid non-empty UUID `request_id`, and the two must differ.
- C4 ✅ verified live, 10/10 runs — distinct UUIDs per event confirmed each time.
- C6 🔧 full rewrite — old file was a `try/catch`-swallowed 4-op smoke test plus a 5s sleep that never spanned one heartbeat interval, testing nothing about liveness or ping/pong.
- **Disposition: CORRECTED-GREEN, 1-3s** (10/10 runs, deterministic) — a major runtime improvement over the old 11s harness-flagged-slow baseline, not a regression. No production bug — doc/spec-link gap only, fixed at the source (same pattern as #52).

## ✅ AUDIT COMPLETE — all 55 active edge-case scenarios closed out (2026-07-12)

Final tally across all 11 phases: 55/55 scenarios audited against all six criteria. Every scenario ended CORRECTED-GREEN, CORRECTED-GREEN-but-flaky, CORRECTED-SKIP-by-design, CORRECTED-RED (blocked by a filed issue), or CORRECTED-(harness-layer-only). Zero scenarios were left in their original ⬜/untouched state.

**Production bugs found and filed (10 issues, ISS-108 through ISS-116, one number reused):**
- **ISS-108** (Medium) — board-gen doesn't guarantee an obstacle adjacent to spawn (~20% flaky), #1.
- **ISS-109** (Medium) — jump-height edge structurally unreachable in `1v1_PVE`, #7.
- **ISS-110** (Medium) — PVE AI initiative RNG can wipe the player's squad before any human turn (~20%), #9.
- **ISS-111** (High) — skill cooldown never decrements anywhere in the repo — real gameplay-balance bug, #10.
- **ISS-112** (Medium) — CLI harness structurally can't reach any admin-gated route's non-admin-rejection path, #17 (also affects #43, #49, #53, #54 as a recurring ceiling, not separately filed each time).
- **ISS-113** (Medium) — character reroll has no post-match/creation-flow gate (also a CP-refund exploit vector, bounded), #21.
- **ISS-114** (Low) — `bootstrapBot`'s teardown hook is single-slot, silently overwritten by a second call (account-orphaning bug), #31 (also affected #30, #34, #38, #39).
- **ISS-115** (Low) — CLI transport client can't omit/spoof the request-id header, #43.
- **ISS-116** (Medium) — admin user registry leaks `full_address`/`birth_date` in plaintext, never censored per the atom's own documented rule, #49.

**Two scenarios ended structurally SKIP/RED by design, not bugs in the test:** #7 (jump-height, 0% reachable in the current arena config) and #21 (reroll, deterministically surfaces the real ISS-113 gap — left RED on purpose per this audit's "honest red over false green" principle while the suite is reporting-only).

**Recurring defect classes found across the audit** (for future authors to watch for, not files needing further action):
1. **Assert-inside-its-own-catch** — a failure assertion living inside the same `try` its own `catch` handles, silently swallowing regressions. Found in ~10 scenarios (#16, #19, #20, #21, #23, #24, #27, and others) — the single most common defect class in the whole audit.
2. **Bare-vs-qualified ATD IDs** — bare atom IDs (e.g. `api_leaderboard`) resolve to a different, zero-coverage phantom-stub object than the module-qualified form (`upsilonapi:api_leaderboard`) that actually carries the real code/test links. Recurred in ~15 scenarios across Phases 6-11.
3. **Phantom `e.status_code` field** — never exists on any CLI-thrown error object (real field is `e.status`); soft-failed silently wherever checked. Recurred in ~8 scenarios.
4. **Total false greens** — zero API calls/assertions, or fabricated formulas/nonexistent fields, ending in an unconditional pass. Found in #16, #17 (partial), #22, #23, #32, #42, #43, #49 (all rewritten to real, reachable edges).
5. **Harness-layer ceilings** — CLI structurally cannot reach a server-side negative path (admin-route rejection, request-id spoofing, SSE channel forgery). 5 confirmed instances (#17/ISS-112, #43/ISS-115, #49, #53, #54) — all resolved via honest "pin what's actually observable" reframes rather than papering over the gap.
6. **Protocol-migration drift** — Phase 11's three scenarios were all still written against the retired WebSocket/Reverb protocol a full migration cycle after the hub moved to SSE; the ATD atom docs had already been updated, but the test files hadn't. All three rewritten to their genuine SSE-era analogues.

**Cleanup follow-ups noted but not actioned during the audit** (flagged in individual findings-log entries above, still open):
- Phantom `req_ui_session_timeout`/`requirement_req_ui_session_timeout` link recurs across 5 files outside any single scenario's scope (#19's finding).
- `edge_auth_password_policy_full`'s dropped confirmation-mismatch sub-case may need separate coverage (#18's finding).
- `trigger_one_ci_test.sh`'s trigger-name normalization is inconsistent across scenarios (#33's finding).

Next step: this suite has been running in reporting-only CI mode since ISS-107 was filed (per `ci_edge_case_reporting.md`'s own governing constraint, see the file's top-level framing). With the full audit now closed, promoting the suite back to a real CI gate is a decision for a human to make, not this audit to enact — the two intentionally-RED scenarios (#7, #21) would need their underlying issues (ISS-109, ISS-113) resolved first, or the gate would need to explicitly except them.

## Post-audit CI verification (2026-07-12, run `29192473723`, commit `e5140e3`)

All audited work committed and pushed across all 10 repos; full CI pipeline **green** (edge suite reporting-only). Edge-suite results, all four failures accounted for:
- ❌ `edge_movement_obstacle_collision` (#1) — **ISS-108**, the documented ~20% board-gen flake, exact expected message.
- ❌ `edge_char_reroll_post_match` (#21) — **ISS-113**, intentionally RED.
- ❌ `edge_admin_private_data_access` (#49) — **ISS-116**, intentionally RED. (Its teardown was also fixed pre-commit to register before the expected-RED assertions, so CI runs no longer orphan `privdata_bot_*` accounts.)
- ❌ `edge_attack_target_out_of_grid` (#13) — **ISS-110** pre-turn PVE squad wipe; corrects the audit's own "not subject to ISS-110" claim (see #13's findings-log correction). Any survival-dependent `1v1_PVE` attack/movement scenario shares this exposure.

No unexplained failures; the CLI-observed SKIPs are the CI runner's multi-agent (`_with_2`) and `.disabled` exclusions plus #7's documented ISS-109 skip. **This closes ISS-107's audit execution; remaining decisions (gate promotion, ISS-108→116 fixes) are tracked in their own issues.**

Note for readers of the CI `edge_case_report.md` artifact: its EC-numbering and per-row "ATD Atom" column come from the report generator's own stale mapping (it still lists pre-audit phantom compound atom names, e.g. `mech_skill_validation_*`). The scenario files and this tracker are the source of truth; the generator's mapping is cosmetic and was not in the audit's scope — candidate for the `trigger_one_ci_test.sh` normalization follow-up already noted above.

