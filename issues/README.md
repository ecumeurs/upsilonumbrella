# Issues

> **Index reconciled 2026-06-19**: all `Resolved` issues (and the now-orphaned
> `ISS-054_investigation_report.md` companion doc) were deleted from this directory
> as part of a cleanup pass — this index now tracks **open issues only**. The
> project-root `README.md` carries an auto-generated table of active issues via
> `issues --update-readme`; **this file is maintained by hand**.

## Open / Active

| Ref | File | Severity | Status | Summary |
|---|---|---|---|---|
| ISS-161 | [ISS-161_20260916_hub_database_url_mismatch.md](ISS-161_20260916_hub_database_url_mismatch.md) | Medium | Open | `start_services.sh` retargets economy/auth's `DATABASE_URL` to their own database but never does the same for the hub, which silently inherits the raw `postgres` db instead of the dedicated `upsilon` database `deploy/initdb` provisions for it — the hub's real schema/data has always lived in `postgres` in dev; `upsilon` sits empty. Found while deepening `check_services.sh`'s DB schema checks |
| ISS-153 | [ISS-153_20260901_temporary_entity_summon_trap_no_producer.md](ISS-153_20260901_temporary_entity_summon_trap_no_producer.md) | Medium | Open | `EntityDuration`/`ExpiresWithCaster` have live production readers (`endofturn.go`, `gamestate_logic.go`) but no producer ever sets them non-default, and `OriginSkillID` is never written; no skill-cast path calls `RegisterBuff` and `BuffTickDown` is never invoked outside its own test. Missing feature work (summons/traps/skill buffs), not a defect — scaffolding for an intended mechanic, per maintainer intent |
| ISS-152 | [ISS-152_20260901_information_level_scheme_never_enforced.md](ISS-152_20260901_information_level_scheme_never_enforced.md) | Low | Open | `InformationLevel`/`MinInfoLevel` is configured across the whole property registry but `UserFriendlyGet` (its only real gate) has zero non-debug call sites; the wire boundary (`output.go convertProperty`/`NewEntity`) never passes a viewer level. NOT a live exposure today — `masking.go` already does real per-recipient field-name masking. Maintainer ruling 2026-09-01: WIRE IT IN decided, RETIRE withdrawn, deferred to a future round; ISS-151 is now a blocking prerequisite for the wire-in, not subordinate to it |
| ISS-151 | [ISS-151_20260901_properties_for_character_public_vs_registry_minlevel.md](ISS-151_20260901_properties_for_character_public_vs_registry_minlevel.md) | Medium | Open | `PropertiesForCharacter` builds HP/Movement/SP/MP/Shield/Attack/AttackRange/Defense/JumpHeight at `Public`, contradicting the registry's `FriendlyController` `MinInfoLevel` for those keys. Test/dev-only (all 16 callers are `_test.go`), no production impact today. Maintainer ruling 2026-09-01 on ISS-152 (wire-in decided, not retired) reframes this from "security theatre, blocked by/subordinate to ISS-152" to a blocking prerequisite: must be fixed before or with the ISS-152 wire-in, or it ships an exposure on day one |
| ISS-150 | [ISS-150_20260901_ruler_leak_test_bypasses_actor_ownership.md](ISS-150_20260901_ruler_leak_test_bypasses_actor_ownership.md) | Medium | Open | `TestRulerEntityLeak` writes `GameState.Entities` directly from the test goroutine after `Start()` has handed ownership to the actor loop, racing production's `getEntitiesState`; the resulting Go `fatal error` kills the whole `ruler` test binary and **silently truncates the package's test count** (189->175 observed). Pre-existing; 1 occurrence in 56 runs; a race-free helper already exists and is unused |
| ISS-149 | [ISS-149_20260830_combat_outcome_trigger_family.md](ISS-149_20260830_combat_outcome_trigger_family.md) | Medium | Open | No entity-attached combat-outcome triggers (on-hit/dodge/parry/miss); existing family is positional-only, the sole hit test conflates miss with dodge, and melee has no hit test at all. Blocks ISS-148 |
| ISS-148 | [ISS-148_20260830_parry_declared_but_unimplemented.md](ISS-148_20260830_parry_declared_but_unimplemented.md) | Medium | Open | Parry is declared, constructible and in `SkillTargetingProperties` but has zero combat read sites; its intended semantics (hit lands, damage forced to the floor of 1, on-hit effects still fire) need an on-hit trigger family that does not exist — all 5 trigger types are positional |
| ISS-146 | [ISS-146_20260827_shield_specific_buff_semantics_deferred.md](ISS-146_20260827_shield_specific_buff_semantics_deferred.md) | Medium | Open | Shield-specific buff semantics (cap, overshield, regen) deferred by decision; Shield treated as a plain resource for now |
| ISS-142 | [ISS-142_20260827_skill_originated_attribute_buffs_unsupported.md](ISS-142_20260827_skill_originated_attribute_buffs_unsupported.md) | High | Open | Skills cannot apply attribute buffs (engine path unwired); seeded buff skills silently run as defaults. **Blocks ISS-140** |
| ISS-139 | [ISS-139_20260826_atd_defects_deferred_from_102_103_130_131_round.md](ISS-139_20260826_atd_defects_deferred_from_102_103_130_131_round.md) | Low | Open | ATD papertrail cleanup — pre-existing defects deferred from the ISS-102/103/130/131 round |
| ISS-137 | [ISS-137_20260826_auth_renewal_logout_revocation_hole.md](ISS-137_20260826_auth_renewal_logout_revocation_hole.md) | Medium | Open | Logout during the sliding-renewal window leaves the freshly-minted replacement token live |
| ISS-136 | [ISS-136_20260826_e2e_friendly_fire_skill_test_flaky.md](ISS-136_20260826_e2e_friendly_fire_skill_test_flaky.md) | Medium | Open | `e2e_friendly_fire_skill_test.js` fails non-deterministically — narrow single-character probe window, not a masking regression |
| ISS-134 | [ISS-134_20260826_go_work_sync_rewrites_submodule_gomod.md](ISS-134_20260826_go_work_sync_rewrites_submodule_gomod.md) | Medium | Open | `go work sync` rewrites submodule `go.mod`/`go.sum` on every CI run — committed manifests have drifted from what the workspace resolves |
| ISS-133 | [ISS-133_20260826_upsilonserializer_not_a_proper_repo.md](ISS-133_20260826_upsilonserializer_not_a_proper_repo.md) | Low | Open | `upsilonserializer` is an in-tree `go.work` module (not a real Git submodule) with a single consumer, `upsilonapi`, used only for `CurrentSerializerVersion` — investigate folding it into `upsilonapi` as an internal package instead of carrying it as a pseudo shared-library module |
| ISS-129 | [ISS-129_20260806_atd_link_placement_file_headers.md](ISS-129_20260806_atd_link_placement_file_headers.md) | Medium | Open | ~60 Go files place `@spec-link`/`@test-link` in the file header instead of atop the function/type — but `CODING_RULE.md` §1 (absolute ban) and `.agent/rules/ATD.md` §252 (ban *unless* the atom covers the file's entire architectural pattern) **contradict each other**, so 60 is an upper bound, not a violation count; resolve the rule conflict first, then re-scan. Root cause behind the ISS-126/ISS-127 link-cap breaches |
| ISS-128 | [ISS-128_20260806_lint_ignore_naive_substring_match.md](ISS-128_20260806_lint_ignore_naive_substring_match.md) | Medium | Open | `code_health_check.py` matches `@lint-ignore-*` by naive whole-file substring, so any file merely *mentioning* a tag silently disables that check on itself — the checker currently skips its own source this way; anchor the match to comment lines and re-baseline |
| ISS-127 | [ISS-127_20260805_user_flows_spec_atd_link_cap.md](ISS-127_20260805_user_flows_spec_atd_link_cap.md) | Medium | Open | `tests/playwright/user_flows.spec.ts` carries 13 ATD link occurrences against the 10 cap (12 distinct atoms), pre-existing (not caused by commit `8a95229`); split the spec along flow boundaries rather than delete links |
| ISS-125 | [ISS-125_20260801_registration_requires_address_birthdate.md](ISS-125_20260801_registration_requires_address_birthdate.md) | Medium | Open | Registration mandates `full_address` + `birth_date`, neither of which gameplay needs — deliberate scope reduction, but codified in a STABLE architecture atom so it needs a documented ATD change, not just a code edit |
| ISS-124 | [ISS-124_20260801_new_account_dashboard_empty_roster.md](ISS-124_20260801_new_account_dashboard_empty_roster.md) | High | Open | New account shows 0 characters — the SPA never called `POST /api/v1/battle/enroll`. Fix landed 2026-08-04 (game-selection page + catalog endpoint + router gate, CI-verified); awaiting user confirmation in the web UI before closing |
| ISS-123 | [ISS-123_20260724_host_side_ci_seed_scripts_superseded.md](ISS-123_20260724_host_side_ci_seed_scripts_superseded.md) | Medium | Open | Host-side seed/trigger scripts (seed_ci.sh + callers) assume a single hub-owned DB and expect `hub -seed` to seed accounts/catalog — false since the auth/economy extraction; superseded by the 6-image docker-compose CI stack. Retire or re-cut for multi-service |
| ISS-122 | [ISS-122_20260723_battleui_profile_requires_enrollment_guard.md](ISS-122_20260723_battleui_profile_requires_enrollment_guard.md) | Medium | Open | battleui reads /api/v1/profile after login without enrolling — now 404s under the game-agnostic model; SPA must enroll-on-entry or guard the 404 (part of battleui's pending phase-4 auth adaptation) |
| ISS-119 | [Ref_20260722_match_start_race_local_env.md](Ref_20260722_match_start_race_local_env.md) | Low | Open | Four match-resolution E2E scenarios act on match.found before the engine's async game-start lands — deterministic local failure (pre-existing, verified on pristine pre-session tree), unobserved on CI runners |
| ISS-118 | [Ref_20260722_gdpr_export_per_game_gap.md](Ref_20260722_gdpr_export_per_game_gap.md) | Medium | Open | Game-agnostic accounts remodel narrows auth's GDPR export to account+registrations; per-game export fragments needed before the Phase-4 cutover leaves data portability incomplete |
| ISS-117 | [Ref_20260722_upsilonapi_dependabot_vulns.md](Ref_20260722_upsilonapi_dependabot_vulns.md) | High | Open | GitHub reports 15 Dependabot vulnerabilities (7 critical) on upsilonapi's default branch; no process surfaces alerts — triage, bump, and add govulncheck to CI |
| ISS-116 | [ISS-116_20260712_admin_users_endpoint_leaks_private_fields.md](ISS-116_20260712_admin_users_endpoint_leaks_private_fields.md) | Medium | Open | Admin User Registry Leaks `full_address`/`birth_date` in Plaintext |
| ISS-115 | [ISS-115_20260711_cli_client_cannot_omit_request_id.md](ISS-115_20260711_cli_client_cannot_omit_request_id.md) | Low | Open | CLI HTTP Client Unconditionally Injects Request ID — "Missing Request ID" Path Untestable via E2E |
| ISS-114 | [ISS-114_20260710_bootstrapbot_teardown_hook_overwrite.md](ISS-114_20260710_bootstrapbot_teardown_hook_overwrite.md) | Low | Open | `bootstrapBot`'s single-slot teardown hook silently drops cleanup for the first of two bots in one agent |
| ISS-113 | [ISS-113_20260710_reroll_no_post_match_gate.md](ISS-113_20260710_reroll_no_post_match_gate.md) | Medium | Open | Character Reroll Has No Post-Match Gate — Documented "Creation Flow Only" Availability Rule Is Unenforced |
| ISS-112 | [ISS-112_20260710_admin_negative_path_untestable_via_cli.md](ISS-112_20260710_admin_negative_path_untestable_via_cli.md) | Medium | Open | CLI Harness Blocks Negative-Path Testing of Admin-Gated Endpoints |
| ISS-111 | [ISS-111_20260710_skill_cooldown_never_decrements.md](ISS-111_20260710_skill_cooldown_never_decrements.md) | High | Open | Skill Cooldown Is Set on Cast but Never Decremented — Permanent Lockout |
| ISS-110 | [ISS-110_20260710_pve_ai_can_sweep_before_player_turn.md](ISS-110_20260710_pve_ai_can_sweep_before_player_turn.md) | Medium | Open | PVE AI Can Wipe the Player's Squad Before the Human Gets a Single Turn |
| ISS-109 | [ISS-109_20260710_jump_height_edge_unreachable.md](ISS-109_20260710_jump_height_edge_unreachable.md) | Medium | Open | Jump-Height Rejection Edge Is Structurally Unreachable via E2E |
| ISS-108 | [ISS-108_20260710_obstacle_not_adjacent_to_spawn.md](ISS-108_20260710_obstacle_not_adjacent_to_spawn.md) | Medium | Open | Board Generation Does Not Guarantee Obstacles Near Spawns |
| ISS-107 | [ISS-107_20260709_edge_case_scenario_suite_audit.md](ISS-107_20260709_edge_case_scenario_suite_audit.md) | Medium | Open | Audit the upsiloncli edge-case scenario suite — it's the scenarios (stale assertions, randomness, timing: ISS-102/103/105 + friendly-fire), not the mechanics, that redden CI; classify/disposition each and decide the edge-step CI policy |
| ISS-106 | [ISS-106_20260709_php_empty_array_skill_payload_start_failure.md](ISS-106_20260709_php_empty_array_skill_payload_start_failure.md) | Low | Open | Data half (PHP-era `[]` skill payloads 400 arena start) vanishes on the prod DB wipe; surviving half: hub `Join` answers `matched` even when engine-start fails, stranding the client on an arena-less match |
| ISS-105 | [ISS-105_20260709_cli_token_starvation_long_fights.md](ISS-105_20260709_cli_token_starvation_long_fights.md) | Low | Open | CLI scenarios idling > 15 min between requests 401 mid-fight (sliding renewal never engages; Sanctum never expired) — flakes `e2e_archetype_pve_full_fight` on long fights |
| ISS-104 | [ISS-104_20260708_matchmaking_parallel_join_queue_poison.md](ISS-104_20260708_matchmaking_parallel_join_queue_poison.md) | High | Open | Parallel matchmaking joins can strand a queue entry; the strand self-perpetuates, pairing every later 1v1_PVE joiner with the previous victim's match (403 on game state) |
| ISS-103 | [ISS-103_20260707_privacy_check_asserts_unimplemented_masking.md](ISS-103_20260707_privacy_check_asserts_unimplemented_masking.md) | Medium | Open | e2e_battle_starts_privacy_check asserts foe-loadout masking neither Laravel nor the hub ever implemented (ISS-077 contract) |
| ISS-100 | [ISS-100_20260616_devcontainer_webgl_playwright_visual.md](ISS-100_20260616_devcontainer_webgl_playwright_visual.md) | Medium | Open | Devcontainer lost WebGL/SwiftShader; Playwright 3D visual specs can't render (env regression) |
| ISS-090 | [ISS-090_20260427_action_endpoint_segregation.md](ISS-090_20260427_action_endpoint_segregation.md) | Medium | Open | All tactical actions funneled through one endpoint; needs segregation |
| ISS-089 | [ISS-089_20260426_mechanic_random_shop_algorithm.md](ISS-089_20260426_mechanic_random_shop_algorithm.md) | Medium | Open | Deterministic daily rotating shop algorithm |
| ISS-087 | [ISS-087_20260426_grid_generator_tuning.md](ISS-087_20260426_grid_generator_tuning.md) | Medium | Open | Generated battle maps consistently mis-sized / mis-densified |
| ISS-082 | [ISS-082_20260425_frontend_playwright_test_seams.md](ISS-082_20260425_frontend_playwright_test_seams.md) | Medium | Open | Playwright HTML report now captured in CI; 2 specs fail + 2 hang (frontend, was tied to now-resolved ISS-084) |
| ISS-081 | [ISS-081_20260425_cross_stack_error_handling.md](ISS-081_20260425_cross_stack_error_handling.md) | Medium | Open | `error_key` only propagated on engine action paths; harmonize cross-stack |
| ISS-080 | [ISS-080_20260425_error_key_atd_and_envelope.md](ISS-080_20260425_error_key_atd_and_envelope.md) | Medium | Open | ATD for `error_key` taxonomy; possible promotion to envelope root |
| ISS-079 | [ISS-079_20260424_cell_access_y_major_standard.md](ISS-079_20260424_cell_access_y_major_standard.md) | Medium | Open | Standardize cell access on Y-major layout via shared helper |
| ISS-078 | [ISS-078_20260423_shielding_credit_attribution.md](ISS-078_20260423_shielding_credit_attribution.md) | Medium | Open | Robust credit attribution for damage mitigation (shield caster) |
| ISS-077 | [ISS-077_20260423_skill_inspection.md](ISS-077_20260423_skill_inspection.md) | Medium | Open | Skill inspection UI/CLI for detailed skill properties |
| ISS-072 | [ISS-072_20260423_pass_choose_facing.md](ISS-072_20260423_pass_choose_facing.md) | Medium | Open | "Pass" action should let player choose facing (anti-backstab) |
| ISS-055 | [ISS-055_20260420_actor_message_validation.md](ISS-055_20260420_actor_message_validation.md) | Low | Open | Actor should validate target message type |
| ISS-049 | [ISS-049_20260418_actor_generics_modernization.md](ISS-049_20260418_actor_generics_modernization.md) | Low | Open | Modernize actor library with Go generics |

---

### Index integrity notes (2026-09-02 cleanup)
- The 6 issues whose `Status` field read `Resolved` were deleted from this
  directory, per the standing convention that it tracks **open issues only**:
  **ISS-140, 141, 143, 144, 145, 147**. Their content is preserved in git history
  under each Ref (`git log --diff-filter=D -- issues/ISS-NNN*`).
  - ISS-141 and ISS-144 were resolved in the write-isolation round (`8363c0a`).
  - ISS-140, 143, 145 and 147 were resolved by the Property Key Space Unification
    round (`b86599f`..`c69a25a`) and closed in `a4ebc33`.
- **Zero dangling markdown links resulted**: a repo-wide scan for `](...ISS-NNN...)`
  found the 6 links only in this index's own table, which was edited in the same
  pass. The many bare `ISS-NNN` mentions left in code comments, atoms and other
  issue files are narrative references, not links, and were deliberately left
  as-is — same treatment as the 2026-08-27 cleanup.
- Directory and index still match 1:1 (57 files / 57 rows); the auto-generated
  root `README.md` table was already at 57 active and is unchanged by the deletion.

### Index integrity notes (2026-08-27 cleanup)
- All 9 issues whose `Status` field read as closed were deleted: **ISS-101, 102,
  120, 121, 126, 130, 131, 132, 135**. (ISS-120 read `Fixed & CI-verified`,
  ISS-101/121 `Resolved — <detail>`; the rest read a bare `Resolved`.) Their
  content is preserved in git history under each Ref.
- 5 now-dangling markdown links to the deleted files (in ISS-134, 137, 138, 139)
  were de-linked to plain `ISS-NNN (resolved; file removed 2026-08-27)` text.
  Narrative mentions of these refs in ISS-107/110/127/128/129/136 were left as-is
  — they are historical context, not links.
- This hand-maintained index had also drifted the other way: **14 open issues had
  no row at all** (ISS-108–116, 134, 136–139). Rows were generated from each
  file's own header and the table re-sorted; it now matches the directory 1:1
  (43 files / 43 rows).
- **ISS-114** carried no `Status:` field at all; set to `Open`.
- **ISS-082** read `Open (reopened 2026-06-16 — …)`. The `issues` CLI matches
  `Status` by **exact** string, so any decoration silently drops the issue from the
  auto-generated root table — ISS-082 had been missing from it. Field normalised to
  a bare `Open`; the reopen detail already lives in the file's `## Update` section.
  Keep `Status:` to one of the four bare values.
- Same exact-match trap on `Severity`: **ISS-049** (`Low (Architectural Improvement)`)
  and **ISS-106** (`Low (downgraded 2026-07-09 — see "Post-wipe update")`) were
  invisible to `issues --severity low`. Both normalised to a bare `Low`; the
  ISS-106 downgrade rationale remains in its `Post-wipe update` section.

### Index integrity notes (2026-06-19 cleanup, round 2)
- Additional issues closed and deleted: ISS-023, 036, 039, 040, 042, 083, 093,
  094, 095, 096, 098, 099. ISS-093 (admin self-destruction), ISS-096 (trap
  TriggerType enforcement), and ISS-099 (AoE zone parsing) were verified fixed
  in code before/at deletion; the others were removed by the maintainer directly.
- No dangling cross-references to these refs were found in the remaining
  issue files.

### Index integrity notes (2026-06-19 cleanup)
- All 16 `Resolved` issues (ISS-054, 065–067, 069–071, 073–074, 084–086, 088,
  091–092, 097) and the companion `ISS-054_investigation_report.md` were deleted.
  Resolved work is preserved in git history (see commits referencing each Ref)
  if it ever needs to be revisited.
- This index now tracks **open issues only**; there is no Resolved section to
  reconcile going forward — closing an issue means deleting its file and this
  line in the same change.

### Index integrity notes (2026-06-16 audit)
- The previous index linked dead `Ref_*` filenames (renamed to `ISS-NNN_*`) and
  several resolved issues whose files no longer exist (ISS-046/047/050–053/063),
  while omitting ~20 issues that do exist. All links above are verified present.
- **ISS-046** (turner hands turn to dead entity) was referenced by the old index
  but has **no file**; its tracking is lost. Not recreated here (per audit scope).
- The `issues` CLI builds links for the **root** README from each file's real
  name; this directory index is maintained by hand and was the stale artifact.
