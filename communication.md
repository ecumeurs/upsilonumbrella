# Upsilon Battle: API Communication Reference

This document provides a comprehensive reference for the communication interfaces between the Vue.js frontend (`upsilonbattleui`), the Upsilon Hub (Go platform gateway), and the Upsilon (Go) Battle Engine.

## 1. Shared Infrastructure

### 1.1 Standard JSON Message Envelope
**Source:** [[api_standard_envelope]]

To guarantee traceability and consistent error handling, every JSON exchange between system units (Vue, Hub, Engine) MUST conform to the following root structure:

- **Event Name:** `board.updated`
- **Payload:** Strictly follows the `[[api_standard_envelope]]` format. The tactical state is located in the `data` field of the envelope. Team-based victory is reported via `winner_team_id`. The state includes an optional `action` object providing explicit data for animations (moves, attacks, passes).
- **Envelope Example:** `{"request_id": "uuid", "success": true, "data": {"match_id": "uuid", "action": {"type": "attack", ...}, ...}}`

```json
{
  "request_id": "018f5a...", // string (UUIDv7): MANDATORY. Chronological sortability. Rules in [[api_request_id]].
  "message": "...",         // string: Intent summary, status message, or error description.
  "success": true,          // boolean: Indicates operational success.
  "data": {},               // object|array|null: Primary payload (e.g., Resource, Collection, or Success DTO).
  "meta": {}                // object: Side information for debugging or testing (optional).
}
```

> [!IMPORTANT]
> **Crash Early Enforcement:** 
> - A request lacking a `request_id` or using an invalid format will immediately return `success: false` with HTTP 400.
> - Any malformed JSON or missing mandatory fields in internal communication will return `success: false` to the gateway.


### 1.2 Request Identification
**Source:** [[api_request_id]]

The `request_id` must be a **string (UUIDv7)**. It is the responsibility of the originator (typically the Vue frontend for user actions) to generate this ID. It must be propagated across all distributed calls spanning the hub and the engine to maintain the trace defined in [[rule_tracing_logging]].

### 1.3 State Versioning & Deduplication
**Source:** [[mech_game_state_versioning]]

To ensure consistency and optimize performance during high-frequency combat, Upsilon uses a monotonic versioning system. 

1. **Versioning:** Every state mutation in the Go Engine increments a `Version` (int64).
2. **De-duplication:** The Go Internal Engine drops outgoing webhooks if the state hasn't progressed since the last transmission.
3. **Gateway Enforcement:** the hub ignores incoming webhooks with a version lower than or equal to the current database state, effectively deduplicating the fan-out. The hub uses the `version` (int64) as the single source of truth for match progression, mapping it to both `version` and legacy `turn` columns.
4. **Broadcast Efficiency:** Clients (Vue/CLI) rely on the `version` field to ensure they are processing the latest tactical state.

### 1.4 Service Ports & Network Topology

| Service | Port (Dev) | Protocol | Role |
| :--- | :--- | :--- | :--- |
| **Caddy Front Door** | `8085` | HTTP | Stable client entrypoint → hub |
| **Upsilon Hub** | `8090` | HTTP | External Gateway, SSE stream & SPA serving |
| **Go Engine** | `8081` | HTTP | Battle computation (internal) |
| **Vue.js (Vite)** | `5173` | HTTP | "Neon in the Dust" Frontend (Dev Only, proxies `/api` to `:8085`) |

> [!TIP]
> **Production Note:** In production, the Vue.js app is pre-built into the hub image (`HUB_SPA_DIR`) and served by the hub behind the front door, eliminating the need for the Vite dev server (Port 5173).

---

## 2. Upsilon Hub (External Gateway)
**Source Module:** [[api_laravel_gateway]]  
**Base URL:** `http://localhost:8085/api/v1` (front door; hub-direct on `:8090`)  
**Authentication:** Bearer Token (opaque personal access tokens, Sanctum-compatible rows; sliding renewal per [[upsilonauth:mech_sanctum_token_renewal]])

### 2.0 API Summary

| Verb | URI | Intent | Specification |
| :--- | :--- | :--- | :--- |
| `POST` | `/auth/register` | User Registration & Roster Creation | [[api_auth_register]] |
| `POST` | `/auth/login` | User Authentication | [[api_auth_login]] |
| `POST` | `/auth/admin/login` | Administrative Authentication (CLI/API) | [[uc_admin_login]] |
| `POST` | `/auth/logout` | Session Termination | [[api_auth_logout]] |
| `POST` | `/auth/update` | Update Security Identity (Address, Email) | [[api_auth_user]] |
| `POST` | `/auth/password` | Rotate Credentials | [[api_auth_user]] |
| `GET` | `/auth/export` | Complete User Data Portability Dump | [[api_profile_export]] |
| `DELETE` | `/auth/delete` | GDPR Right to be Forgotten (Account Deletion) | [[api_auth_user]] |
| `GET` | `/profile` | Get Player Bio & Roster Overview | [[customer_player_profile]] |
| `GET` | `/profile/characters` | List Player Roster | [[api_profile_character]] |
| `GET` | `/profile/character/{id}` | Get Character Details | [[api_profile_character]] |
| `GET` | `/profile/credits` | Get Lightweight Credit Balance | [[api_profile_character]] |
| `POST` | `/profile/character/{id}/reroll` | Reset Stats (New Accounts) | [[api_profile_character]] |
| `POST` | `/profile/character/{id}/upgrade` | Attribute Point Allocation | [[api_profile_character]] |
| `POST` | `/profile/character/{id}/rename` | Character Cosmetic Identity Rename | [[rule_character_renaming]] |
| `DELETE` | `/profile/character/{id}` | Remove Character from Roster | [[api_profile_character]] |
| `POST` | `/matchmaking/join` | Enter Battle Queue | [[api_matchmaking]] |
| `GET` | `/matchmaking/status` | Poll Match Status | [[api_matchmaking]] |
| `DELETE` | `/matchmaking/leave` | Exit Battle Queue | [[api_matchmaking]] |
| `GET` | `/match/stats/waiting` | Get Queue Density Metrics | [[ui_dashboard_match_statistics]] |
| `GET` | `/match/stats/active` | Get Live Match Count | [[ui_dashboard_match_statistics]] |
| `GET` | `/game/{id}` | Get Cached Board State | [[api_battle_proxy]] |
| `POST` | `/game/{id}/action` | Proxy Tactical Action to Engine | [[api_battle_proxy]] |
| `POST` | `/game/{id}/forfeit` | Standalone Forfeit Route | [[rule_forfeit_battle]] |
| `GET` | `/admin/users` | List Users for Auditing (Cursor Based) | [[uc_admin_user_management]] |
| `POST` | `/admin/users/{account_name}/anonymize` | GDPR Anonymization | [[uc_admin_user_management]] |
| `DELETE` | `/admin/users/{account_name}` | Administrative Soft Delete | [[uc_admin_user_management]] |
| `GET` | `/admin/history` | List All Match History (Cursor Based) | [[uc_admin_history_management]] |
| `DELETE` | `/admin/history/purge` | Clean up match history older than 90 days | [[uc_admin_history_management]] |
| `GET` | `/events` | Realtime SSE Stream (§2.8) | [[api_websocket_game_events]] |
| `POST` | `/api/webhook/upsilon` | Ingest Engine State Update (Internal) | [[api_go_webhook_callback]] |
| `GET` | `/admin/shop-items` | List All Shop Items (Admin) | [[api_shop_item_admin_crud]] |
| `POST` | `/admin/shop-items` | Create New Shop Item (Admin) | [[api_shop_item_admin_crud]] |
| `GET` | `/admin/skill-templates` | List All Skill Templates (Admin) | [[api_skill_template_admin_crud]] |
| `POST` | `/admin/skill-templates` | Create New Skill Template (Admin) | [[api_skill_template_admin_crud]] |
| `GET` | `/leaderboard` | Global Rankings (Mode-based) | [[api_leaderboard]] |
| `GET` | `/shop/items` | Browse V2.0 Shop Catalog | [[upsilonapi:api_shop_browse]] |
| `POST` | `/shop/purchase` | Purchase Item (debit credits, add to inventory) | [[upsilonapi:api_shop_purchase]] |
| `GET` | `/profile/inventory` | List Owned Items + Equip Status | [[upsilonapi:api_inventory_list]] |
| `GET` | `/profile/character/{id}/equipment` | Get Character 3-Slot Equipment | [[upsilonapi:api_equipment_management]] |
| `POST` | `/profile/character/{id}/equip` | Equip Item (slot inferred) | [[upsilonapi:api_equipment_management]] |
| `DELETE` | `/profile/character/{id}/unequip/{slot}` | Unequip Slot (armor / utility / weapon) | [[upsilonapi:api_equipment_management]] |



### 2.1 Authentication

#### `POST /auth/register`
- **Specification:** [[api_auth_register]]
- **Intent:** [[uc_player_registration]]: Allow new users to create an account and receive an initial characters roster.
- **Input:**
  - `account_name`: `string`
  - `email`: `string` (must be unique)
  - `password`: `string` (minimum 15 characters)
  - `password_confirmation`: `string` (must match password)
  - `full_address`: `string` (Mandatory per [[uc_player_registration]])
  - `birth_date`: `string (ISO8601)` (Mandatory per [[uc_player_registration]])
- **Output:**
  - `user`: `UserResource` (See [[#4.4-userresource]])
  - `token`: `string` (JWT Bearer Token)

#### `POST /auth/login`
- **Specification:** [[api_auth_login]]
- **Intent:** [[uc_player_login]]: Authenticate existing users and provide a session token.
- **Input:**
  - `account_name`: `string` [Mandatory]
  - `password`: `string` [Mandatory]
- **Output:**
  - `user`: `UserResource` (See [[#4.4-userresource]])
  - `token`: `string` (JWT Bearer Token)

#### `POST /auth/admin/login`
- **Specification:** [[uc_admin_login]]
- **Intent:** Authenticate administrators for CLI or high-privilege API access.
- **Input:**
  - `account_name`: `string` [Mandatory]
  - `password`: `string` [Mandatory]
- **Validation:** Must have `Admin` role.
- **Output:**
  - `user`: `UserResource` (See [[#4.4-userresource]])
  - `token`: `string` (JWT Bearer Token)

#### `POST /auth/logout`
- **Specification:** [[api_auth_logout]]
- **Intent:** [[uc_auth_logout]]: Terminate the active session for Player or Admin and revoke the current access token.
- **Security:** Requires bearer authentication.
- **Output:** `null` (successful status code 200 with standard success envelope).

#### `POST /auth/update`
- **Specification:** [[api_auth_user]]
- **Intent:** Update security identity information for the logged-in user.
- **Input:**
  - `account_name`: `string` (unique)
  - `email`: `string` (unique email format)
  - `birth_date`: `string (DATE)`
  - `full_address`: `string`
- **Output:** Updated `UserResource`.

#### `POST /auth/password`
- **Specification:** [[api_auth_user]]
- **Intent:** Update account password.
- **Input:**
  - `current_password`: `string`
  - `password`: `string` (min 15 chars)
  - `password_confirmation`: `string`
- **Output:** Standard success envelope.

#### `GET /auth/export`
- **Specification:** [[api_profile_export]], [[rule_gdpr_compliance]], [[upsilonauth:service_gdpr_export_orchestrator]]
- **Intent:** Auth-owned, Auth-orchestrated GDPR data portability export. Aggregates
  Auth's own account/registration/token data with the Economy fragment and, when the
  caller is enrolled, the Tactical fragment.
- **Authentication:** Requires authenticated user.
- **Success (`200`):** Standard success envelope whose `data` is `authv1.GDPRExport`
  (see `upsilontypes/authv1/gdpr_export.go`):
  - `schema_version`: `string` (currently `"authv1.gdpr-export.v1"`)
  - `generated_at`: `string (RFC3339 UTC)`
  - `complete`: `bool` — always `true` on a `200`; there is no partial success.
  - `included_fragments`: `Array<string>` — ordered `["auth","economy"]`, plus
    `"tactical"` only when the caller is enrolled in tactical.
  - `auth`: `{ account: {account_name, email, role, full_address, birth_date, created_at, updated_at, deleted_at}, registrations: [], tokens: [] }`
    (no internal account UUID, no credentials, no token hashes/bearer values).
  - `economy`: `{schema_version, wallet, inventory, credit_ledger, inventory_ledger}`.
  - `tactical`: `battlev1.GDPRExportFragment` — **omitted entirely** (no key at all,
    not a null placeholder) when the owner is not enrolled in tactical.
  - Response carries `Content-Disposition: attachment; filename="upsilon_identity_export.json"`.
- **Failure (fail-closed, `503`):** If any required fragment collection is incomplete,
  the endpoint returns `503` with the standard error envelope (`data: null`, no
  attachment header) and `meta`:
  - `reason`: `"export_incomplete"`
  - `missing_fragments`: `Array<{name: string, reason: string}>`

#### `DELETE /auth/delete`
- **Specification:** [[api_auth_user]]
- **Intent:** Terminate account and anonymize sensitive data.
- **Output:** Standard success envelope.


### 2.2 Profile & Character Management

> Contracts unchanged from the Laravel gateway (ported at migration Phase 5).

#### `GET /profile`
- **Specification:** [[customer_player_profile]]
- **Intent:** Retrieve global player statistics, win/loss ratio, and basic roster overview.
- **Output:** `UserResource` (loaded with characters).

#### `GET /profile/characters`
- **Specification:** [[api_profile_character]]
- **Intent:** List all characters associated with the authenticated player's roster.
- **Output:** `Array<CharacterResource>` (See [[#4.5-characterresource]])

#### `GET /profile/character/{characterId}`
- **Specification:** [[api_profile_character]]
- **Intent:** Retrieve detailed statistics and status for a specific character.
- **Input:**
  - `characterId`: `string (UUID)` (URL Parameter - Match ID)
- **Output:** `CharacterResource` (See [[#4.5-characterresource]])

#### `POST /profile/character/{characterId}/reroll`
- **Specification:** [[api_profile_character]]
- **Intent:** [[uc_player_registration]] (Step 4): Allow fresh accounts to reroll their starting character stats.
- **Restriction:** Restricted to "New" accounts; forbidden after match participation.
- **Input:**
  - `characterId`: `string (UUID)` (URL Parameter)
- **Output:**
  - `character`: `CharacterResource` (The updated character)
  - `reroll_count`: `int` (The user's total reroll count)

#### `POST /profile/character/{characterId}/upgrade`
- **Specification:** [[api_profile_character]]
- **Intent:** [[uc_progression_stat_allocation]]: Manually allocate attribute points earned through wins.
- **Input:**
  - `characterId`: `string (UUID)` (URL Parameter)
  - `stats`: `object`
    - `hp`: `int` (increment amount, optional)
    - `attack`: `int` (increment amount, optional)
    - `defense`: `int` (increment amount, optional)
    - `movement`: `int` (increment amount, optional)
- **Validation:** Must adhere to [[rule_progression]] (Attribute Cap: `10 + wins`).
- **Output:** `CharacterResource` (The updated character)

#### `POST /profile/character/{characterId}/rename`
- **Specification:** [[rule_character_renaming]]
- **Intent:** Update the cosmic display name of a character.
- **Input:**
  - `characterId`: `string (UUID)` (URL Parameter)
  - `name`: `string`
- **Output:** `CharacterResource` (The updated character)

#### `DELETE /profile/character/{characterId}`
- **Specification:** [[api_profile_character]]
- **Intent:** Remove a character from the roster.
- **Input:**
  - `characterId`: `string (UUID)` (URL Parameter)
- **Output:** Standard success envelope.


### 2.3 Matchmaking & Queue

> Contracts unchanged from the Laravel gateway (ported at migration Phase 4);
> `match.found` reaches the SPA over the SSE stream (§2.8).

#### `POST /matchmaking/join`
- **Specification:** [[api_matchmaking]]
- **Intent:** [[uc_matchmaking]]: Enter the queue for a specific game mode.
- **Input:**
  - `game_mode`: `string` ("1v1_PVP", "2v2_PVP", "1v1_PVE", "2v2_PVE")
- **Output:** 
  - `status`: `string` ("queued" | "matched")
  - `match_id`: `string (UUID)|null`
  - `expected_participants`: `int`
  - `empty_slots`: `int`

#### `GET /matchmaking/status`
- **Specification:** [[api_matchmaking]]
- **Intent:** [[uc_matchmaking]]: Poll for matchmaking updates or match assignment.
- **Logic:** For an active match, verifies the arena still exists in the engine
  ([[api_arena_existence_check]]) and attempts resurrection from the cached board
  state when it does not (ISS-054); a failed or impossible resurrection concludes
  the match server-side (`status: "idle"`, message explains the loss).
- **Output:** 
  - `status`: `string` ("queued" | "matched" | "idle")
  - `match_id`: `string (UUID)|null`
  - `expected_participants`: `int|null`
  - `empty_slots`: `int|null`
  - `queued_at`: `string (ISO8601)|null`

#### `DELETE /matchmaking/leave`
- **Specification:** [[api_matchmaking]]
- **Intent:** Cancel queue entry and return to Dashboard.
- **Output:** `null` (successful status code 200 with standard success envelope).

### 2.4 Game Interaction (Proxy)

#### `GET /game/{id}`
- **Specification:** [[api_battle_proxy]]
- **Intent:** Retrieve the **cached** board state from the hub's database.
- **Logic:** Avoids direct engine overhead by reading the last known state synced via webhook.
- **Input:**
  - `id`: `string (UUID)` (URL Parameter - Match ID)
- **Output:** `GameMatchResource` (See [[#4.6-gamematchresource]])
#### `POST /game/{id}/action`
- **Specification:** [[api_battle_proxy]]
- **Intent:** [[uc_combat_turn]]: Proxy tactical commands to the Upsilon Go Engine.
- **Input:**
  - `id`: `string (UUID)` (URL Parameter - Match ID)
  - `payload`: `ArenaActionRequest` (Note: `player_id` is automatically injected and validated by the hub)
- **Logic:** Validates that the authenticated user owns the targeted `entity_id` before proxying the request to the engine via [[api_go_battle_action]]. Includes `skill_id` for 'skill' actions.
- **Output:** `ArenaActionResponse` (See [[#4.1-arenaactionrequest]])

#### `POST /game/{id}/forfeit`
- **Specification:** [[rule_forfeit_battle]]
- **Intent:** Allow a player to concede the match.
- **Input:**
  - `id`: `string (UUID)` (URL Parameter - Match ID)
- **Logic:** Calls standalone forfeit logic in the engine. Bypasses the need for `entity_id`.
- **Constraint:** Can only be called during a turn owned by the authenticated player (Enforced by Engine).
- **Output:** Standard Success Envelope.

### 2.5 Shop, Inventory & Equipment (ISS-074)

> Every credit/wallet/market mutation runs through the hub's economy
> seam (ledger + wallet in one transaction).

#### `GET /shop/items`
- **Specification:** [[upsilonapi:api_shop_browse]]
- **Intent:** List the V2.0 catalog of purchasable items.
- **Output:** `Array<ShopItemResource>` — `{ id, name, type, slot, properties, cost, available }`.

#### `POST /shop/purchase`
- **Specification:** [[upsilonapi:api_shop_purchase]]
- **Intent:** Atomic credit-debit + inventory upsert + audit log.
- **Input:**
  - `shop_item_id`: `string (UUID)` [Mandatory]
  - `quantity`: `int` (Optional, default 1, max 99)
- **Output:** `{ credits: <new_balance>, inventory_item: InventoryItemResource }`
- **Failure modes:** 422 with `meta.reason ∈ {insufficient_credits, quantity_cap, item_unavailable}`; 404 unknown item.

#### `GET /profile/inventory`
- **Specification:** [[upsilonapi:api_inventory_list]]
- **Intent:** List authenticated user's owned items, annotated with current equip binding.
- **Output:** `Array<InventoryItemResource>` — each row includes `equipped_on: { character_id, character_name, slot } | null`.

#### `GET /profile/character/{id}/equipment`
- **Specification:** [[upsilonapi:api_equipment_management]]
- **Intent:** Get the 3-slot equipment configuration for a character.
- **Output:** `CharacterEquipmentResource` — `{ character_id, armor, utility, weapon }`. Each slot is either `null` or a populated `InventoryItemResource`.

#### `POST /profile/character/{id}/equip`
- **Specification:** [[upsilonapi:api_equipment_management]]
- **Intent:** Equip an inventory item; slot inferred from item type.
- **Input:** `{ item_id: <player_inventory_uuid> }`
- **Behavior:** Cross-character mutual exclusivity is enforced atomically: equipping an item already bound to another character of the same user clears that prior binding in the same DB transaction.
- **Output:** Updated `CharacterEquipmentResource`.

#### `DELETE /profile/character/{id}/unequip/{slot}`
- **Specification:** [[upsilonapi:api_equipment_management]]
- **Intent:** Clear a single equipment slot. `slot ∈ {armor, utility, weapon}`.
- **Output:** Updated `CharacterEquipmentResource`. Returns 404 if the slot was already empty.

### 2.6 Social & Competitive

> The hand-built envelope (no top-level `meta`) is preserved from the
> Laravel implementation.

#### `GET /leaderboard`
- **Specification:** [[api_leaderboard]]
- **Intent:** Retrieve global rankings for a specific battle mode, filtered by the current weekly cycle.
- **Input:**
  - `mode`: `string` ("1v1_PVP", "2v2_PVP", "1v1_PVE", "2v2_PVE") [Mandatory]
  - `page`: `int` (Default: 1)
- **Rules Applied:**
  - [[rule_leaderboard_score_calculation]]: Scoring formula.
  - [[rule_leaderboard_cycle]]: Temporal filter (Current Week).
- **Output:**
  - `results`: `Array<RankingResource>` (Rank, Account Name, Wins, Losses, Score) - Paginated (10 per page).
  - `self`: `RankingResource|null` (Current user's ranking context).
  - `meta`: `PaginationMeta`

### 2.7 Administrative Management

> Facet-shaped API endpoints (locked no-Inertia decision — future
> `/admin/v1`). The SPA's admin pages consume these endpoints directly.

#### `GET /admin/dashboard`
- **Specification:** [[ui_admin_dashboard]]
- **Intent:** Retrieve administrative overview and system statistics.
- **Authentication:** Requires `Admin` role.
- **Output:**
  - `total_users`: `int`
  - `active_matches`: `int`
  - `total_matches_today`: `int`
  - `system_health`: `object`

#### `GET /admin/users`
- **Specification:** [[uc_admin_user_management]]
- **Intent:** List all user accounts for auditing purposes (excluding private data).
- **Authentication:** Requires `Admin` role.
- **Input:**
  - `cursor`: `string (ISO8601)` (Optional: for sequential pagination)
  - `search`: `string` (Optional: filter by account name)
- **Output:**
  - `items`: `Array<AdminUserResource>`
  - `next_cursor`: `string|null`
  - `has_more`: `boolean`
- **Privacy Note:** Private fields (full_address, birth_date) are excluded per [[rule_admin_access_restriction]].

#### `DELETE /admin/users/{account_name}`
- **Specification:** [[uc_admin_user_management]]
- **Intent:** Perform soft delete of user account (GDPR compliance).
- **Authentication:** Requires `Admin` role.
- **Input:**
  - `account_name`: `string` (URL Parameter)
- **Logic:** Sets `deleted_at` timestamp but preserves data for integrity.
- **Output:** Standard Success Envelope.

#### `POST /admin/users/{account_name}/anonymize`
- **Specification:** [[uc_admin_user_management]]
- **Intent:** Execute "Right to be Forgotten" - anonymize sensitive user data.
- **Authentication:** Requires `Admin` role.
- **Input:**
  - `account_name`: `string` (URL Parameter)
- **Logic:** Overwrites `full_address` and `birth_date` with "ANONYMIZED" placeholder.
- **GDPR Reference:** Implements [[rule_gdpr_compliance]] anonymization requirement.
- **Output:** Standard Success Envelope.

#### `GET /admin/history`
- **Specification:** [[uc_admin_history_management]]
- **Intent:** Retrieve match history for administrative audit and maintenance.
- **Authentication:** Requires `Admin` role.
- **Input:**
  - `cursor`: `string (ISO8601)` (Optional)
  - `search`: `string` (Optional)
- **Output:**
  - `items`: `Array<MatchHistoryResource>`
  - `next_cursor`: `string|null`
  - `has_more`: `boolean`

#### `DELETE /admin/history/purge`
- **Specification:** [[uc_admin_history_management]]
- **Intent:** Clean up match history older than 90 days (maintenance).
- **Authentication:** Requires `Admin` role.
- **Logic:** Soft delete match records older than 90 days per GDPR retention policies.
- **Output:** 
  - `purged_count`: `int`
  - Standard Success Envelope

### 2.10 Admin Catalog Management (ISS-086)

#### `GET /admin/shop-items`
- **Specification:** [[api_shop_item_admin_crud]]
- **Intent:** List all items, including those marked as unavailable.
- **Output:** `Array<ShopItemResource>`

#### `POST /admin/shop-items`
- **Specification:** [[api_shop_item_admin_crud]]
- **Intent:** Create a new shop item (including D11 exotic items).
- **Input:** 
  - `name`: `string`
  - `slot`: `armor|utility|weapon`
  - `cost`: `int`
  - `properties`: `object` (JSON map of engine properties)
  - `skill_template_id`: `string (UUID)` (Optional)
- **Output:** `ShopItemResource`

#### `GET /admin/skill-templates`
- **Specification:** [[api_skill_template_admin_crud]]
- **Intent:** List all skill templates in the registry.
- **Output:** `Array<SkillTemplateResource>`

#### `POST /admin/skill-templates`
- **Specification:** [[api_skill_template_admin_crud]]
- **Intent:** Create a new skill template for item/entity binding.
- **Input:**
  - `name`: `string`
  - `behavior`: `Direct|Reaction|Passive|Counter|Trap`
  - `grade`: `I|II|III|IV|V`
  - `weight_positive`: `int`
  - `weight_negative`: `int`
  - `targeting`: `object` (Structured JSON map)
  - `costs`: `object` (Structured JSON map)
  - `effect`: `object` (Structured JSON map)
- **Output:** `SkillTemplateResource`


### 2.8 Realtime Stream (SSE)

Real-time updates ride **Server-Sent Events** from the hub (migration doc 03, Phase 3).
The stream replaced the Laravel Reverb/Pusher websocket; the WebSocket tier is
decommissioned since the Phase 6 cutover.

#### `GET /api/v1/events`
- **Specification:** [[api_websocket_game_events]]
- **Intent:** One authenticated stream per user carrying all private realtime events
  (the connection *is* the user's private channel — no channel-auth handshake,
  no channel key).
- **Authentication:** `Authorization: Bearer {token}` — like any API call. Sliding token
  renewal does not ride the stream; tokens renew on regular REST traffic.
- **Input (headers):**
  - `Last-Event-ID`: `{match_id}:{version}` (optional) — on reconnect the hub replays the
    current board snapshot if newer (only the latest state is persisted; replay is a
    snapshot, not an event log). Participant-gated.
- **Output:** `text/event-stream`; each event is `id: {match_id}:{version}`,
  `event: {event name}`, `data: {Standard JSON Envelope}` with the fog-of-war-masked board
  state in `data` (masked per recipient, `message: "Board Updated"`).
- **Heartbeat:** comment frame every ~25s (proxy keep-alive/buffering guard).

#### Key Events
- `match.found`: Matchmaking success (hub-emitted since Phase 4; envelope
  `message: "Match Found"`, `data: {match_id, game_mode}`, delivered to the matched
  humans only). The frame carries no `id:` line — nothing to replay; a reconnecting
  client learns about its match from `/matchmaking/status`.
- `game.started`: Arena initialization complete.
- `turn.started`: New entity initiative active (starts 30s clock).
- `board.updated`: Position change, stat change, or successful tactical action (Move, Attack, Pass).
- `game.ended`: Win condition met or match terminated.

### 2.9 Advanced Identity Management

> GDPR data portability lives at `GET /auth/export` (§2.1) — Auth-owned and
> Auth-orchestrated. There is no separate `/profile/export` route; the route
> that historically lived here (Laravel-era `user`/`characters`/`match_history`/
> `exported_at` shape) has been removed. See §2.1 for the current contract.

#### `PUT /profile/personal-data`
- **Specification:** (Planned - Not Yet Implemented)
- **Intent:** Allow users to update personal information (address, birth date).
- **Authentication:** Requires authenticated user.
- **Input:**
  - `full_address`: `string`
  - `birth_date`: `string` (ISO8601)
- **Validation:** Must maintain data quality and compliance standards.
- **Output:** Updated `UserResource`

#### `GET /profile/match-history`
- **Specification:** (Planned - Not Yet Implemented)
- **Intent:** Retrieve authenticated user's personal match history.
- **Authentication:** Requires authenticated user.
- **Input:**
  - `page`: `int` (Default: 1)
  - `game_mode`: `string` (Optional filter)
- **Output:**
  - `results`: `Array<PersonalMatchHistoryResource>`
  - `meta`: `PaginationMeta`

---

## 3. Internal Infrastructure (Appendix)

This section documents internal-facing interfaces that are **NOT** reachable from outside the secure cluster. These are intended for engine development and cluster orchestration.

### 3.1 Upsilon API (Go Combat Engine)
**Source Module:** [[api_go_battle_engine]]  
**Base URL:** `http://localhost:8081/v1` (Internal Only)

#### `GET /health`
- **Specification:** [[api_go_health_check]]
- **Intent:** Lightweight readiness probe for engine status.
- **Output:** `{ "status": "ok", "revision": "string" }`

#### `POST /arena/start`
- **Specification:** [[api_go_battle_start]]
- **Intent:** Initialize a tactical arena instance. Supports AI archetypes via `auto_gen` and `archetype` fields.
- **Input:** `ArenaStartRequest` (JSON)

#### `POST /arena/{id}/action`
- **Specification:** [[api_go_battle_action]]
- **Intent:** [[uc_combat_turn]]: Validate and execute tactical actions (Move, Attack, Pass).
- **Input:** `ArenaActionRequest` (JSON)

#### `POST /arena/{id}/forfeit`
- **Specification:** [[api_go_battle_forfeit]]
- **Intent:** Allow a player to concede the match without an entity context.
- **Input:** `ArenaForfeitRequest` (JSON)

#### `GET /arena/{id}/exists`
- **Specification:** [[api_arena_existence_check]]
- **Intent:** Verify if an arena instance exists in engine memory.
- **Output:** `ArenaExistsResponse` (JSON)

#### `POST /skills/generate`
- **Specification:** [[api_skill_generation]]
- **Intent:** Generate a random balanced skill based on optional constraints.
- **Input:** `SkillGenerateRequest` (JSON)
- **Output:** `SkillGenerateResponse` (JSON)

### 3.2 Asynchronous Webhook (Callback)
**Destination:** `POST /api/webhook/upsilon` (on the hub, via the front door) — Must be reachable internally from the Go Engine.

#### Webhook Event Payload
- **Specification:** [[api_go_webhook_callback]]
- **Event Types:** `game.started`, `turn.started`, `board.updated`, `game.ended`.
- **Data Payload:** `ArenaEvent` which contains a `BoardState`.

---

## 4. Common Data Structures

### 4.1 Arena DTOs

#### ArenaActionResponse
- **`status`**: `string`

#### CreditAward
- **`player_id`**: `string (UUID)`
- **`amount`**: `int`
- **`source`**: `string` ("damage", "healing", "status")

#### ArenaStartResponse
- **`arena_id`**: `string (UUID)`
- **`initial_state`**: `BoardState`

#### ArenaActionRequest
- **`player_id`**: `string (UUID)` [MANDATORY] (Injected by Gateway for external calls)
- **`entity_id`**: `string (UUID)` [MANDATORY]
- **`type`**: `string` [MANDATORY] ("move", "attack", "skill", "pass")
- **`skill_id`**: `string (UUID)` [MANDATORY for 'skill']
- **`target_coords`**: `Array<Position>` [MANDATORY for 'move', 'attack', and 'skill']

#### AdminShopItemRequest
- **`name`**: `string`
- **`slot`**: `string` ("armor", "utility", "weapon")
- **`cost`**: `int`
- **`properties`**: `object` (Structured JSON Map: `{"WeaponBaseDamage": 10}`)
- **`skill_template_id`**: `string (UUID)` (Optional)

#### AdminSkillTemplateRequest
- **`name`**: `string`
- **`behavior`**: `string` ("Direct", "Reaction", "Passive", "Counter", "Trap")
- **`grade`**: `string` ("I", "II", "III", "IV", "V")
- **`weight_positive`**: `int`
- **`weight_negative`**: `int`
- **`targeting`**: `object` (Structured JSON Map)
- **`costs`**: `object` (Structured JSON Map)
- **`effect`**: `object` (Structured JSON Map)

#### ArenaForfeitRequest
- **`player_id`**: `string (UUID)` [MANDATORY]

#### ActionFeedback
- **`type`**: `string` ("move", "attack", "skill", "pass")
- **`actor_id`**: `string (UUID)`
- **`target_id`**: `string (UUID)` (Legacy/Primary target)
- **`path`**: `Array<Position>` (For 'move')
- **`results`**: `Array<ActionResult>` (See below)
- **`credits`**: `Array<CreditAward>` (Optional)

#### ActionResult
- **`target_id`**: `string (UUID)`
- **`damage`**: `int` (Optional)
- **`heal`**: `int` (Optional)
- **`prev_hp`**: `int`
- **`new_hp`**: `int`
- **`credits`**: `Array<CreditAward>` (Optional)

#### ArenaStartRequest
- **`match_id`**: `string (UUID)` [MANDATORY]
- **`callback_url`**: `string` [MANDATORY] (Webhook URL - Must be reachable internally by the Go Engine)
- **`players`**: `Array<Player>` [MANDATORY] (At least one player required)


### 4.2 Arena Components

#### BoardState
**Specification:** [[api_go_battle_engine]]

Defines the complete state of a tactical arena at a specific moment in time.

| Field | Type | Description |
| :--- | :--- | :--- |
| `players` | `Array<Player>` | Consolidated roster of participants and their live entities. |
| `grid` | `Grid` | The tactical map structure. |
| `turn` | `Array<Turn>` | Sequence of actors based on initiative. |
| `current_player_is_self` | `boolean` | **Gateway Only:** True if the current user is the acting player. Masked from Go's `current_player_id`. |
| `current_entity_id` | `string (UUID)` | ID of the entity currently acting. |
| `timeout` | `string (ISO8601)` | Timestamp when the current turn expires. |
| `start_time` | `string (ISO8601)` | Timestamp when the arena started. |
| `version` | `int64` | Monotonic sequence number for state changes. Required for deduplication. [[mech_game_state_versioning]] |
| `winner_team_id` | `int?` | ID of the winning team (if match finished). 0 or null if draw. |
| `action` | `object` | Optional. Explicit details about the last action for UI animations. |
| `version` | `int64` | State version (Bit-packed: turn << 32 \| action). |

#### Grid
The engine is a true 3D grid. The API exposes a 2D projection of **the topmost cell at each `(x, y)` column** — i.e. the walkable surface. Caves and underground are not exposed in this iteration.

- **`width`**: `int` — columns along X.
- **`height`**: `int` — rows along Y (grid depth; not elevation).
- **`max_height`**: `int` — engine Z ceiling (exclusive upper bound). Clients rendering elevation should scale vertical features against this value.
- **`cells`**: `Array<Array<Cell>>` (width-major 2D matrix: `cells[x][y]`).

#### Cell
A cell represents the topmost (surface) cell at its `(x, y)` column.

- **`entity_id`**: `string (UUID)|null`
- **`obstacle`**: `boolean`
- **`height`**: `int` — Z index of this topmost cell. Used by 3D clients for terrain elevation; 2D clients (CLI ASCII) may shade glyphs or ignore it entirely.

#### Turn
- **`player_id`**: `string (UUID)`
- **`entity_id`**: `string (UUID)`
- **`delay`**: `int`

#### Position
**Specification:** [[api_go_battle_engine]]
- **`x`**: `int`
- **`y`**: `int`

### 4.3 Entity & Player

#### Entity
**Specification:** [[entity_character]]

Detailed state of a single actor.

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `string (UUID)` | Unique identifier for the entity. |
| `is_self` | `boolean` | True if the entity belongs to the requesting player. |
| `team` | `int` | Team identifier. |
| `name` | `string` | Display name. |
| `hp` | `int` | Current Hit Points. Dead units are marked with `hp: 0`. |
| `max_hp` | `int` | Maximum Hit Points. |
| `archetype` | `string` | Optional: "fighter"\|"ranger"\|"support"\|"sneak". |
| `auto_gen` | `boolean` | True → Go generates stats and skills from archetype+grade. |
| `dead` | `boolean` | True if the character has been eliminated in this session. |
| `attack` | `int` | Base offensive power. |
| `defense` | `int` | Base defensive mitigation. |
| `move` | `int` | Remaining movement range for the current turn. |
| `max_move` | `int` | Total movement range attribute. |
| `position` | `Position` | Current `{x, y}` coordinates. |

#### Player
- **`is_self`**: `boolean` (True if this is the requesting user)
- **`nickname`**: `string`
- **`team`**: `int`
- **`ia`**: `boolean` (True if controlled by engine)
- **`archetype`**: `string` (Optional: default archetype for entities)
- **`total_wins`**: `int` (Used to derive grade if `ia` is true)
- **`entities`**: `Array<Entity>`

### 4.4 UserResource
**Specification:** [[api_laravel_gateway]]

| Field | Type | Description |
| :--- | :--- | :--- |
| `account_name` | `string` | Displayed name. |
| `role` | `string` | User's role (e.g., 'Player', 'Admin'). |
| `email` | `string` | User's email address. |
| `full_address` | `string` | User's residential address. |
| `birth_date` | `string (ISO8601)` | User's date of birth. |
| `total_wins` | `int` | Total career wins. |
| `total_losses` | `int` | Total career losses. |
| `ratio` | `float` | Win/Loss ratio. |
| `reroll_count` | `int` | Number of times starter stats were rerolled. |
| `credits` | `int` | Current credit balance. |
| `characters` | `Array<CharacterResource>` | Optional: Loaded character list. |

### 4.5 CharacterResource
**Specification:** [[api_profile_character]]

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `string (UUID)` | Character's unique identifier. |
| `name` | `string` | Display name. |
| `hp` | `int` | Character's Hit Points. |
| `attack` | `int` | Character's Attack stat. |
| `defense` | `int` | Character's Defense stat. |
| `movement` | `int` | Current movement range. |
| `initial_movement`| `int` | Base movement range (for cap calculation). |

### 4.6 GameMatchResource
**Specification:** [[api_battle_proxy]]

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `string (UUID)` | Match unique identifier. |
| `game_mode` | `string` | e.g., "1v1_PVP". |
| `started_at` | `string (ISO8601)` | Start timestamp. |
| `concluded_at` | `string (ISO8601)\|null` | End timestamp. |
| `winner_team_id` | `int|null` | Winning team identifier. |

### 4.7 ArenaEvent
**Specification:** [[api_go_webhook_callback]]

Payload for the asynchronous engine callback.

| Field | Type | Description |
| :--- | :--- | :--- |
| `match_id` | `string (UUID)` | The platform Match ID. |
| `event_type` | `string` | e.g., `game.started`, `turn.started`. |
| `player_id` | `string (UUID)` | Optional: Targeted player. |
| `entity_id` | `string (UUID)` | Optional: Targeted entity. |
| `data` | `BoardState` | The current state of the board. |
| `version` | `int64` | Monotonic sequence number (synced with `data.sequence`). |
| `timeout` | `string (ISO8601)` | End of the current turn clock. |

---

## 5. Traceability Matrix

| Endpoint | Specification | Use Case (usecase.md) | Business Requirement (BRD.md) |
| :--- | :--- | :--- | :--- |
| `POST /auth/register` | [[api_auth_register]] | [[uc_player_registration]] | 2.1 User Onboarding & Identity |
| `POST /auth/login` | [[api_auth_login]] | [[uc_player_login]] | 2.1 User Onboarding & Identity |
| `POST /profile/character/{id}/reroll` | [[api_profile_character]] | [[uc_player_registration]] (Step 4) | 2.1 frictionless Entry |
| `POST /profile/character/{id}/upgrade` | [[api_profile_character]] | [[uc_progression_stat_allocation]] | 2.5 Character Progression |
| `POST /matchmaking/join` | [[api_matchmaking]] | [[uc_matchmaking]] | 2.3 Matchmaking Ecosystem |
| `POST /game/{id}/action` | [[api_battle_proxy]] | [[uc_combat_turn]] | 2.4 Combat Engine & Action Economy |
| `POST /api/webhook/upsilon` | [[api_go_webhook_callback]] | [[uc_combat_turn]] / [[uc_match_resolution]] | Internal Callback |
| `GET /api/v1/auth/export` | [[api_profile_export]] / [[rule_gdpr_compliance]] / [[upsilonauth:service_gdpr_export_orchestrator]] | Data Portability | GDPR |
| `POST /auth/logout` | [[api_auth_logout]] | [[uc_auth_logout]] | Security |
| `GET /v1/arena/{id}/exists` | [[api_arena_existence_check]] | State Synchronization | Internal API |
| `POST /v1/skills/generate` | [[api_skill_generation]] | Procedural Content | Internal API |
| `Universal Envelope` | [[api_standard_envelope]] | All Interactions | Traceability |
| `GET /leaderboard` | [[api_leaderboard]] | Rankings | Social |
