# Upsilon: A Multi-Service Game Platform

**Upsilon** is a multi-service game platform, umbrella-repo'd across Git submodules and governed end to end by the Atomic Traceable Documentation (ATD) framework. Today it ships one live game — **UpsilonBattle**, a turn-based Tactical RPG (TRPG) for concurrent multiplayer combat and AI skirmishes — served through a shared platform gateway (`upsilonhub`) alongside extracted substrate services for identity (`upsilonauth`) and economy (`upsiloneconomy`). The v3 trajectory grows this into a four-game platform (battle, tycoon, spy, digital) composed on shared platform substrates and vocabularies, with the standing rule that **games never import games**. The full architecture reference set — service ownership map, platform direction, and the [playbook for adding a new service](architecture/how_to_add_a_service.md) — starts at [`architecture/INDEX.md`](architecture/INDEX.md).

## Battle: The Game At a Glance
- **Play Modes:** 1v1 (PvE or PvP) and 2v2 (PvE or PvP).
- **The Board:** A randomly generated rectangular grid (5-15 tiles per dimension, absolute minimum area of 50 tiles) containing up to 10% randomly placed impassable obstacles.
- **Victory Condition:** Eliminate all characters on the opposing team. **Friendly Fire is strictly disabled.**
- **The Roster:** Every player commands a roster of exactly 3 characters.

## Character System & Progression
- **Initial Core Roll:** New characters start with base stats (3 HP, 1 Move, 1 Attack, 1 Def) and exactly 4 additional points are randomly dispatched (Total 10 points). 
- **The Reroll Mechanic:** During account registration, players are granted an option to completely re-randomize their 3 initial character stat blocks. This reroll can be executed a strict maximum of **3 times**.
- **Stat Progression:** Securing a match victory rewards a player with 1 Attribute Point. 
  - **Constraints:** Total attributes cannot exceed `10 + total wins`. Matches result in a maximum of 1 point gain.
  - **Movement Restriction:** Upgrading the Movement attribute is heavily throttled and locked to once every 5 accumulated wins.

## Combat Mechanics
- **Initiative & Delay:** Turn order is non-linear. Characters roll a pre-initiative value ranging from `1-500`. Active turns fire when the ticker hits `0`. 
- **Action Economy:** During a turn, a character may perform a maximum of **1 Move** (`+20/tile`), **1 Attack** (`+100`), or safely **Pass** (`+300`). Performing actions accumulates a numerical "Delay Cost," mathematically extending the wait time until that character's next sequence.
- **The Shot Clock:** Active combat turns mandate a strict **30-second limit** per character. Failing to confirm an action manually results in an auto-pass forced by the server, accompanied by a penalty of `+100` (Total `+400` delay).

## Modular Architecture
The Upsilon platform is built as a modular multi-repo system. Each core component is maintained in its own repository and integrated into this umbrella project as a formal **Git Submodule** (`upsilonserializer` is the one exception — an in-tree Go module, not a submodule).

### Repository Structure
1. **Frontend (`upsilonbattleui`)**:
   - Standalone Vue 3 + Vite SPA (vue-router, Tailwind CSS, TresJS 3D) — the player/battle client plus the admin pages.
   - Served by the hub; talks to `/api/v1` with bearer tokens and listens on the SSE event stream.

2. **Platform Gateway (`upsilonhub`)**:
   - Go service — the platform gateway hosting the remaining platform substrates and game modules as packages (matchmaking, admin, character, realtime SSE, the database schema, and today's only shipped game module: battle).
   - One image serves the API + SPA, runs migrations (`-migrate-mode`) and seeds (`-seed`).

3. **Identity Service (`upsilonauth`)**:
   - Extracted auth/identity substrate (SSO-bound target). Owns accounts, tokens, admin user registry and per-account service registrations; the hub validates tokens against it over S2S. Registering never implies enrollment — an account binds to a game only through that game's own opt-in enroll call, surfaced via the hub's games catalog (`GET /api/v1/games`) and the SPA's game-selection page; enrollment is additive-only, never revoked.

4. **Economy Service (`upsiloneconomy`)**:
   - Extracted economy substrate — wallets, ledger, purchases/awards — consumed by the hub (and, over time, every game) over the internal S2S surface.

5. **Platform Kit (`upsilonplatform`)**:
   - Shared mechanical kit (envelope/`respond`, injected clock, observability/OTel setup, database, durable jobs, S2S `httpx`) that every extracted service composes on, so new services are born instrumented instead of copy-drifting the plumbing.

6. **Backend API (`upsilonapi`)**:
   - The battle engine's "Bridge" — a high-performance Go JSON API handling match state, engine callbacks and account/character statistics for the battle game.

7. **Battle Engine (`upsilonbattle`)**:
   - The "calculating brain" that governs active combat sequences.
   - Mathematically simulates initiative, movement validation, and damage systems.

8. **Journey Explorer CLI (`upsiloncli`)**:
   - An interactive terminal tool for API exploration and verification.
   - Supports "Autopilot" sessions to simulate full player journeys.

9. **Shared Assets & Utilities**:
   - `upsilonmapdata`: Geometric board data and obstacle definitions.
   - `upsilonmapmaker`: Procedural generation tools for game boards.
   - `upsilontools`: Common TRPG utilities and helper functions.
   - `upsilontypes`: Shared type definitions and domain models used across all modules.
   - `upsilonserializer`: In-tree (non-submodule) Go module for engine-state serialization.

10. **AWS Infrastructure (`upsilonaws`)**:
   - Bash-based provisioning scripts for deploying the full stack to AWS (eu-west-3).
   - Manages: VPC, EC2 (t3.medium), RDS PostgreSQL 15, Route 53 DNS, nginx + Let's Encrypt SSL.
   - Public endpoint: [upsilon-hub.com](https://upsilon-hub.com) — run `setup.sh` to provision, `teardown.sh` to wipe everything.
   - Designed for pay-per-session use (~$0.075/hour, $0.50/month for Route 53 zone).

## Setup

The Upsilon project is a complex ecosystem. For a detailed guide on how to prepare your environment, install dependencies, and configure the system, please refer to the **[Setup Documentation](Setup.md)**.

## Getting Started

### Cloning the Project
Since the project relies on submodules, you must clone recursively to fetch all components:
```bash
git clone --recursive git@github.com:ecumeurs/upsilonumbrella.git
```
If you have already cloned the repository, initialize the submodules with:
```bash
git submodule update --init --recursive
```

### Development & Monitoring

#### DevContainer Environment
The project provides a pre-configured development environment via **[.devcontainer/](.devcontainer/)**. This is the recommended way to develop for Upsilon, ensuring a consistent environment across all platforms.

- **Stack:** Go, Node.js 20.
- **Tools:** Postgres client and ATD integration tools.
- **Port Forwarding:**
  - `8085`: Caddy front door (hub API + SSE + SPA)
  - `8090`: Upsilon Hub (direct)
  - `8091`: Upsilon Auth (identity/SSO, direct)
  - `8092`: Upsilon Economy (internal-only, direct)
  - `8081`: Upsilon Engine (Go API)
  - `5173`: Vue Frontend (Vite dev server, HMR)

> **Running hub feature tests:** they boot throwaway Postgres containers via
> testcontainers — Docker must be reachable from the environment running
> `go test ./upsilonhub/...`.

#### Service Management
The project includes a suite of scripts in the `scripts/` directory for local service management and testing.

**First-time dev bring-up sequence** (inside the devcontainer):
```bash
./scripts/build_services.sh   # build engine, hub, CLI binaries + SPA
./scripts/seed_ci.sh          # migrate (-migrate-mode full) + seed a fresh DB — required once
./scripts/start_services.sh   # launch engine (:8081), hub (:8090), Vite (:5173)
./scripts/trigger_one_ci_test.sh e2e_customer_onboarding   # run one CLI-backed e2e test
```
> The hub does **not** auto-migrate on boot; `seed_ci.sh` is the one-shot that
> applies the schema and seeds the catalog / test accounts. `trigger_one_ci_test.sh`
> drives the CLI against the Caddy front door via `UPSILON_BASE_URL`
> (`http://proxy:8085` in compose, `http://localhost:8085` from the host) —
> the only entry point that routes both `/api/v1/auth/*` (to `upsilonauth`)
> and the hub API.

- **[scripts/start_services.sh](scripts/start_services.sh)**: Launches the full Upsilon stack (Upsilon Engine, Upsilon Hub, and Vite dev server) in the background. It automatically verifies that all ports are listening before exiting.
- **[scripts/stop_services.sh](scripts/stop_services.sh)**: Gracefully stops all tracked services and ensures ports are freed.
- **[scripts/check_services.sh](scripts/check_services.sh)**: Lightweight status utility for quick health checks of the local stack.
- **[scripts/watch_services.go](scripts/watch_services.go)**: Real-time TUI dashboard for monitoring CPU/Mem usage and recent errors across all services. Run with `go run scripts/watch_services.go`.
- **[scripts/trigger_all_ci_tests.sh](scripts/trigger_all_ci_tests.sh)**: Executes the full local test suite (E2E + Edge Cases) against the running local stack.

#### Development Utilities
- **[scripts/build_services.sh](scripts/build_services.sh)**: Rebuilds the core binaries (Engine, Hub, CLI) and the SPA bundle.
- **[scripts/clear_matches.sh](scripts/clear_matches.sh)**: Authoritatively clears active match records from the database and engine cache.
- **[scripts/seed_ci.sh](scripts/seed_ci.sh)**: Resets and seeds the database with standard CI testing data.
- **[scripts/zombie_killer.sh](scripts/zombie_killer.sh)**: Forcefully kills any orphaned Upsilon processes (CLI bots, detached engines).
- **[scripts/stress_test.py](scripts/stress_test.py)**: High-concurrency performance orchestration script for load testing.
- **[scripts/repo_status.sh](scripts/repo_status.sh)**: One-shot source-control health check across the umbrella **and all submodules** — branch, short HEAD, push-sync (ahead/behind upstream), submodule-pointer coherence, and working-tree cleanliness, in a single aligned table. Pass `--fetch` to refresh remote-tracking refs first. Exits non-zero if any repo is dirty, has unpushed commits, lacks an upstream, or the umbrella points at a commit that isn't the submodule's checked-out HEAD — making it a handy **pre-/post-push preflight** for this multi-repo tree.

## Continuous Integration & Quality control

UpsilonBattle employs a robust CI/CD pipeline via GitHub Actions to ensure code quality, architectural integrity, and business rule compliance.

### Automated Workflow (`.github/workflows/ci.yml`)
A single **CI Pipeline** runs three staged jobs on push / PR to `main`:
- **Build & Lint**: static analysis (Go vet), verifies all core components build, and checks the Docker images.
- **Go Unit Tests**: Go unit tests for all backend modules (including the hub's testcontainers feature suites).
- **Integration & E2E**: orchestrates the ephemeral [docker-compose.ci.yaml](docker-compose.ci.yaml) stack and runs the `upsiloncli` customer + edge scenario suites — specialized CLI bots simulating real player journeys through the hub and engine.

### Code Health Standards (`scripts/code_health_check.py`)
Upsilon defines strict maintainability standards across all supported languages (Go, Python, JS, TypeScript, Vue, PHP). The checker is **available but not automated**: it is not wired into the pre-commit hook (currently disabled there) and is not run in CI. It should be run **manually at the end of each development session** — `python3 scripts/code_health_check.py [path]`, where `path` is a single file or a directory (defaults to the current directory) — to keep code quality from degrading over time. A full-repo run completes in well under a second.

- **File Length:** Warning above 400 effective LOC, Error above 600 LOC.
- **Complexity:** Function nesting depth must not exceed 4 levels.
- **Documentation:** Every function needs an intent comment; missing docs on exported functions is an Error.
- **ATD Traceability:** Each file must link 1-10 distinct ATD atoms via `@spec-link`/`@test-link` tags (warn above 5 distinct). Repeating the same atom ID across multiple tags counts once, not per occurrence. Under 1 or over 10 distinct atoms results in an Error.
- **Validity:** All `@spec-link` IDs must resolve to a valid ATD Atom in the `docs/` directory.

**Exemptions:**
Individual checks can be bypassed using specific tags:
- `@lint-ignore-file-bloating`
- `@lint-ignore-complexity`
- `@lint-ignore-documentation`
- `@lint-ignore-atd`

### CI Infrastructure (Docker Stack)
The project utilizes a dedicated **[docker-compose.ci.yaml](docker-compose.ci.yaml)** to spin up an ephemeral testing environment. This stack is optimized for speed and reliability.

- **Components:**
  - `db`: Postgres 18-alpine database (per-service DBs: `upsilon`, `upsilonauth`, `upsiloneconomy`, on one shared Postgres instance).
  - `hub-migrate` / `hub-seed`: hub-image init containers (schema + seed).
  - `hub`: the platform gateway serving API + SSE + SPA; reaches `auth`/`economy` over S2S.
  - `auth-migrate` / `auth-seed` / `auth`: the extracted `upsilonauth` identity service.
  - `economy-migrate` / `economy-seed` / `economy`: the extracted `upsiloneconomy` service.
  - `proxy`: Caddy front door on `:8085` (its healthcheck gates the stack; routes `/api/v1/auth/*` and `/api/v1/admin/users*` straight to `auth`).
  - `engine`: The Upsilon Battle Engine (Go).
  - `tester`: The Upsilon CLI running in integration mode.
- **Usage:**
  ```bash
  docker compose -f docker-compose.ci.yaml up -d --wait
  ```

- **CI Reports**: Each run generates a summary report ([ci_report.sh](tests/ci_report.sh)) that is attached to the job summary, providing immediate visibility into test outcomes and compliance status.

## Specification (ATD) Maps
All fundamental mechanics, structural constraints, entities, and network rules that form the game are housed individually within the project-specific `docs/` folders (e.g., `upsilonapi/docs/`, `upsilonbattle/docs/`) governed by the ATD Workspace. These Atoms serve as the uncompromising basis for evaluating developer implementation logic.

## Open Issues

| Name | Date | Status | Severity | Oneliner |
|---|---|---|---|---|
| [upsilonapi default branch carries 15 Dependabot vulnerabilities (7 critical)](issues/Ref_20260722_upsilonapi_dependabot_vulns.md) | 2026-07-22 | Open | High | On pushing to `ecumeurs/upsilonapi` (2026-07-22, go.work-sync dependency comm... |
| [Five match-resolution E2E scenarios race engine game-start and fail on dev machines](issues/Ref_20260722_match_start_race_local_env.md) | 2026-07-22 | Open | Low | The four scenarios act on a match immediately after the SSE `match.found` eve... |
| [GDPR erasure still leaves purchase history intact — `player_inventory`/`inventory_transactions` need a pseudonymize-vs-erase decision](issues/ISS-167_20260918_gdpr_erasure_inventory_purge_undecided.md) | 2026-09-18 | Open | Medium | ISS-165's fix (worktree `upsilon-hub-iss-165`, reviewed OKAY, not yet merged)... |
| [GDPR export atoms omit the fail-closed guarantee and the tactical key-omission rule](issues/ISS-166_20260917_gdpr_atoms_understate_fail_closed_contract.md) | 2026-09-17 | Open | Low | ISS-118's post-task ATD sync verified the shipped export against its three go... |
| [77 atoms across eight projects have no usable `## EXPECTATION` section — 29 as empty stubs, 48 absent entirely](issues/ISS-164_20260916_expectation_section_gap_across_atom_corpus.md) | 2026-09-16 | Open | Medium | `atd lint` reports "Missing mandatory section: ## EXPECTATION" for 77 atoms s... |
| [ATD pre-commit orphan check reads `layer` only, ignoring `.atd`'s `OrphanExcludedTypes`, so it disagrees with `atd`'s own tooling](issues/ISS-163_20260916_precommit_orphan_check_ignores_excluded_types.md) | 2026-09-16 | Open | Medium | `scripts/hooks/pre-commit` is a git hook (not yet installed into `.git/hooks`... |
| [upsilonapi predates the platform kit — no OTel, no shared plumbing, and its name no longer fits](issues/ISS-162_20260916_upsilonapi_not_on_platform_kit.md) | 2026-09-16 | Open | Medium | `upsilonhub`, `upsilonauth`, and `upsiloneconomy` all compose on `upsilonplat... |
| [Poison-only traps silently deal attack-scaled bonus damage because absent DamageScale defaults to 100](issues/ISS-160_20260902_poisontrap_damagescale_absent_bonus_damage.md) | 2026-09-02 | Open | Medium | `DamageScale` **defaults to 100 when the key is absent** — absence is not zer... |
| [Nine test sites file a Cost property into the Targeting map under the key "TargetType" — passing only by accident of GetProperty's cross-map scan](issues/ISS-159_20260902_leech_tests_cost_filed_under_targeting.md) | 2026-09-02 | Open | Low | Nine sites do: |
| [The battle client reads a targeting wire shape the engine never sends — `TargetType` silently falls back to 'Entity' and `Zone` is unreachable](issues/ISS-158_20260902_battleui_targeting_wire_shape_mismatch.md) | 2026-09-02 | Open | Medium | The frontend reads targeting properties as `{ value: ... }` for **all** kinds... |
| [A bare-int `Range` in an authored skill produces an inverted, unreachable [value,max] window — Fireball, Heal and Lightning Strike are untargetable](issues/ISS-157_20260902_bare_int_range_inverted_unreachable.md) | 2026-09-02 | Open | High | `Range` is an `IntCounter` (`value` = **minimum** range, `max` = **maximum** ... |
| [The admin skill-template endpoint accepts arbitrary unregistered property keys with 201 Created — registry validation is deferred to battle time](issues/ISS-156_20260902_admin_skill_template_no_registry_validation.md) | 2026-09-02 | Open | Medium | `POST`/`PUT` on `/api/v1/admin/skill-templates` validate only that the `targe... |
| [Shield Bash is seeded as a Reaction but the reaction mechanism does not exist — needs an OnReceivedHit trigger that fires the recipient's reaction back at the attacker](issues/ISS-155_20260902_shield_bash_reaction_onreceivedhit.md) | 2026-09-02 | Open | Medium | `Shield Bash` **should remain a `Reaction`** — it is the vehicle for building... |
| [Regen Aura is seeded as a Passive but no passive/aura mechanism exists — it needs a self-centred Square:1 OnTurn healing zone and a real test bed](issues/ISS-154_20260902_regen_aura_passive_zone_unimplemented.md) | 2026-09-02 | Open | Medium | `Regen Aura` **should remain `Passive`** — the name is correct and it behaves... |
| [The summon/trap temporary-entity family has a fully built consumer side but no producer — nothing ever creates a temporary entity or a skill-originated buff](issues/ISS-153_20260901_temporary_entity_summon_trap_no_producer.md) | 2026-09-01 | Open | Medium | `EntityDuration` and `ExpiresWithCaster` are fully wired on the *consumer* si... |
| [The `InformationLevel` / `MinInfoLevel` per-property visibility scheme has no enforcement point on the live path — it is configured across the registry but never consulted](issues/ISS-152_20260901_information_level_scheme_never_enforced.md) | 2026-09-01 | Open | Low | `InformationLevel` (`property.go:17-33`) is an ordered visibility scale — `Pu... |
| [`PropertiesForCharacter` builds five properties at `Public`, contradicting the registry's declared `MinInfoLevel`](issues/ISS-151_20260901_properties_for_character_public_vs_registry_minlevel.md) | 2026-09-01 | Open | Medium | `PropertiesForCharacter()` (`upsilontypes/property/def/entity.go:91-107`) con... |
| [`TestRulerEntityLeak` mutates `GameState` directly after `Start()`, racing the actor loop and aborting the whole `ruler` test binary](issues/ISS-150_20260901_ruler_leak_test_bypasses_actor_ownership.md) | 2026-09-01 | Open | Medium | Running `go test ./...` in `upsilonbattle` can abort the entire `battlearena/... |
| [No combat-outcome trigger family (on-hit / on-dodge / on-parry / on-miss) attached to entities](issues/ISS-149_20260830_combat_outcome_trigger_family.md) | 2026-08-30 | Open | Medium | Requested by the user (2026-08-30): a trigger family for **combat outcomes** ... |
| [Parry is declared and constructible but never read — and its semantics need an on-hit trigger that does not exist](issues/ISS-148_20260830_parry_declared_but_unimplemented.md) | 2026-08-30 | Open | Medium | `Parry` is a fully declared `SkillProperties` key with a working constructor ... |
| [Shield-specific buff semantics are deferred — Shield is treated as a plain resource for now](issues/ISS-146_20260827_shield_specific_buff_semantics_deferred.md) | 2026-08-27 | Open | Medium | `Shield` is a resource-like counter with mechanics none of the other resource... |
| [Skills cannot apply attribute buffs — the engine path is unwired, and the seeded buff skills silently do something else](issues/ISS-142_20260827_skill_originated_attribute_buffs_unsupported.md) | 2026-08-27 | Open | High | **Primary purpose of this issue: make skills that buff character attributes a... |
| [ATD papertrail cleanup — pre-existing defects deferred from the ISS-102/103/130/131 round](issues/ISS-139_20260826_atd_defects_deferred_from_102_103_130_131_round.md) | 2026-08-26 | Open | Low | A documentalist D2 blast-radius pass over the ISS-102/103/130/131 round surfa... |
| [`e2e_friendly_fire_skill_test.js` fails non-deterministically — narrow single-character probe window, not a masking regression](issues/ISS-136_20260826_e2e_friendly_fire_skill_test_flaky.md) | 2026-08-26 | Open | Medium | `e2e_friendly_fire_skill_test.js` is flaky: three isolated runs against the l... |
| [upsilonserializer is a single-consumer in-tree module masquerading as a shared library — evaluate folding it into upsilonapi](issues/ISS-133_20260826_upsilonserializer_not_a_proper_repo.md) | 2026-08-26 | Open | Low | `upsilonserializer` is listed in `CLAUDE.md`/`UPSILON.md` as one of the share... |
| [~60 Go files carry `@spec-link`/`@test-link` in the file header, and the two governing rule documents disagree on whether that is allowed](issues/ISS-129_20260806_atd_link_placement_file_headers.md) | 2026-08-06 | Open | Medium | A repo-wide scan finds **~60 Go files with at least one `@spec-link`/`@test-l... |
| [`code_health_check.py` matches `@lint-ignore-*` tags by naive whole-file substring, silently skipping any file that merely *mentions* them](issues/ISS-128_20260806_lint_ignore_naive_substring_match.md) | 2026-08-06 | Open | Medium | `code_health_check.py` decides whether to suppress a check by testing `if '<t... |
| [`user_flows.spec.ts` breaches the 10-link ATD cap (13 occurrences / 12 distinct atoms), pre-existing](issues/ISS-127_20260805_user_flows_spec_atd_link_cap.md) | 2026-08-05 | Open | Medium | `upsilonbattleui/tests/playwright/user_flows.spec.ts` carries **13 `@spec-lin... |
| [New account shows 0 characters on the dashboard (SPA never calls battle/enroll)](issues/ISS-124_20260801_new_account_dashboard_empty_roster.md) | 2026-08-01 | Open | High | A freshly registered account shows 0 characters on the dashboard, persisting ... |
| [host-side CI seed/trigger scripts assume a single hub-owned DB — superseded by the 6-image compose stack](issues/ISS-123_20260724_host_side_ci_seed_scripts_superseded.md) | 2026-07-24 | Open | Medium | `scripts/seed_ci.sh` resets **one** database (`$DATABASE_URL`), runs `upsilon... |
| [battleui reads /api/v1/profile after login without enrolling — now 404s under the game-agnostic model](issues/ISS-122_20260723_battleui_profile_requires_enrollment_guard.md) | 2026-07-23 | Open | Medium | Phase-4's game-agnostic remodel makes `GET /api/v1/profile` **battle-scoped**... |
| [CLI HTTP Client Unconditionally Injects Request ID — "Missing Request ID" Path Untestable via E2E](issues/ISS-115_20260711_cli_client_cannot_omit_request_id.md) | 2026-07-11 | Open | Low | `upsiloncli`'s HTTP client (`Client.Do` in `upsiloncli/internal/api/client.go... |
| [`bootstrapBot`'s single-slot teardown hook silently drops cleanup for the first of two bots in one agent](issues/ISS-114_20260710_bootstrapbot_teardown_hook_overwrite.md) | 2026-07-10 | Open | Low | `jsBootstrapBot` (`bridge_battle.go:231-296`) assigns `a.GoTeardownHook` as a... |
| [Character Reroll Has No Post-Match Gate — Documented "Creation Flow Only" Availability Rule Is Unenforced](issues/ISS-113_20260710_reroll_no_post_match_gate.md) | 2026-07-10 | Open | Medium | `upsilonbattle/docs/mech_character_reroll.atom.md` — the atom the `reroll` ha... |
| [CLI Harness Blocks Negative-Path Testing of Admin-Gated Endpoints](issues/ISS-112_20260710_admin_negative_path_untestable_via_cli.md) | 2026-07-10 | Open | Medium | `upsiloncli`'s scripting bridge hard-blocks any `admin_`-prefixed route call ... |
| [Skill Cooldown Is Set on Cast but Never Decremented — Permanent Lockout](issues/ISS-111_20260710_skill_cooldown_never_decrements.md) | 2026-07-10 | Open | High | `paySkillCost` sets `sk.Cooldown = skpc.GetMaxValue()` when a skill is cast (... |
| [PVE AI Can Wipe the Player's Squad Before the Human Gets a Single Turn](issues/ISS-110_20260710_pve_ai_can_sweep_before_player_turn.md) | 2026-07-10 | Open | Medium | Turn initiative in `1v1_PVE` matches is decided by a per-entity random delay ... |
| [Jump-Height Rejection Edge Is Structurally Unreachable via E2E](issues/ISS-109_20260710_jump_height_edge_unreachable.md) | 2026-07-10 | Open | Medium | The jump-height move-validation edge (`entity.path.notvalid`, mechanic rule 9... |
| [Board Generation Does Not Guarantee Obstacles Near Spawns](issues/ISS-108_20260710_obstacle_not_adjacent_to_spawn.md) | 2026-07-10 | Open | Medium | The `entity.path.obstacle` move-validation edge (mechanic #7 of `[[mech_move_... |
| [Audit the upsiloncli edge-case scenario suite — scenario assertions, not mechanics, are what fail CI](issues/ISS-107_20260709_edge_case_scenario_suite_audit.md) | 2026-07-09 | Open | Medium | After the Phase 6 CI green-up (submodule token, engine/CLI image builds, Ryuk... |
| [CLI scenarios that idle past TokenTTL between requests 401 mid-fight](issues/ISS-105_20260709_cli_token_starvation_long_fights.md) | 2026-07-09 | Open | Low | Hub tokens have `TokenTTL = 15m` with sliding renewal after 10m (`identity.go... |
| [Parallel joins can strand a queue entry that then poisons every later 1v1_PVE join](issues/ISS-104_20260708_matchmaking_parallel_join_queue_poison.md) | 2026-07-08 | Open | High | `Matchmaker.Join` enqueues the joiner, then takes `QueueHead(scope, required)... |
| [e2e_battle_starts_privacy_check asserts foe-loadout masking that no stack ever implemented](issues/ISS-103_20260707_privacy_check_asserts_unimplemented_masking.md) | 2026-07-07 | Open | Medium | `e2e_battle_starts_privacy_check` asserts foe entities expose no `equipped_sk... |
| [Devcontainer lost WebGL — Playwright 3D visual specs cannot render](issues/ISS-100_20260616_devcontainer_webgl_playwright_visual.md) | 2026-06-16 | Open | Medium | Headless Chromium in the current devcontainer **cannot create a WebGL context... |
| [Action Endpoint Segregation](issues/ISS-090_20260427_action_endpoint_segregation.md) | 2026-04-27 | Open | Medium | Currently, all tactical actions (move, attack, skill, pass) are funneled thro... |
| [Deterministic Daily Random Shop](issues/ISS-089_20260426_mechanic_random_shop_algorithm.md) | 2026-04-26 | Open | Medium | Implementation of a daily rotating shop system that provides a deterministic ... |
| [Grid Generator Tuning - Large and Flat Maps](issues/ISS-087_20260426_grid_generator_tuning.md) | 2026-04-26 | Open | Medium | Since the integration of the `gridgenerator`, battle maps have been observed ... |
| [Front-end Playwright suite + component-isolation visual regression](issues/ISS-082_20260425_frontend_playwright_test_seams.md) | 2026-04-25 | Open | Medium | The `battleui` front-end was rewritten around `@tresjs/core` (Vue + three.js ... |
| [Cross-stack error handling harmonization](issues/ISS-081_20260425_cross_stack_error_handling.md) | 2026-04-25 | Open | Medium | `error_key` is currently propagated only on the engine action paths (`POST /g... |
| [ATD for `error_key` taxonomy and possible envelope promotion](issues/ISS-080_20260425_error_key_atd_and_envelope.md) | 2026-04-25 | Open | Medium | `error_key` is now plumbed end-to-end (engine ruler → upsilonapi handler → La... |
| [Standardize cell access on Y-major layout](issues/ISS-079_20260424_cell_access_y_major_standard.md) | 2026-04-24 | Open | Medium | The tactical grid is currently serialized width-major (`cells[x][y]`) by the ... |
| [Shielding Credit Attribution System](issues/ISS-078_20260423_shielding_credit_attribution.md) | 2026-04-23 | Open | Medium | Design and implement a robust system for attributing credits earned through d... |
| [Skill Inspection Command](issues/ISS-077_20260423_skill_inspection.md) | 2026-04-23 | Open | Medium | Implement skill inspection functionality allowing players to view detailed sk... |
| [Player Choosing Facing Direction on Pass](issues/ISS-072_20260423_pass_choose_facing.md) | 2026-04-23 | Open | Medium | When a player chooses to "Pass" their turn, they must be given the option to ... |
| [Actor Message Type Validation](issues/ISS-055_20260420_actor_message_validation.md) | 2026-04-20 | Open | Low | The `Actor` implementation should validate if the target message is of the co... |
| [Modernize Actor Library with Go Generics (Templates)](issues/ISS-049_20260418_actor_generics_modernization.md) | 2026-04-18 | Open | Low | The current Actor implementation was designed before Go 1.18 (Generics). It r... |

