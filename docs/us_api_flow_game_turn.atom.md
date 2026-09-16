---
id: us_api_flow_game_turn
status: STABLE
layer: BUSINESS
priority: 3
tags: flow,game,combat,turn,api
dependents:
  - [[upsilonapi:api_websocket]]
human_name: Tactical Game Turn API Flow
type: USER_STORY
version: 1.0
parents:
  - [[requirement_customer_api_first]]
  - [[uc_combat_turn]]
---

# Tactical Game Turn API Flow

## INTENT
To detail the exact API interaction sequence required for a complete tactical turn in a match.

## THE RULE / LOGIC
### Step 1: Turn Awareness
- **Action**: `GET /api/v1/game/{match_id}`
- **Validation**: Check `game_state.current_entity_id` and ensuring it maps to a character under the player's control.

### Step 2: Movement Phase
- **Action**: `POST /api/v1/game/{match_id}/action`
- **Payload**: 
  ```json
  {
    "player_id": "...",
    "entity_id": "...",
    "type": "MOVE",
    "target_coords": [{ "x": 1, "y": 2 }]
  }
  ```
- **Intent**: Reposition the combatant on the grid.

### Step 3: Attack Phase
- **Action**: `POST /api/v1/game/{match_id}/action`
- **Payload**: 
  ```json
  {
    "player_id": "...",
    "entity_id": "...",
    "type": "ATTACK",
    "target_coords": [{ "x": 2, "y": 2 }]
  }
  ```
- **Intent**: Strike an adjacent or in-range enemy.

### Step 4: Turn Finalization
- **Action**: `POST /api/v1/game/{match_id}/action`
- **Payload**: 
  ```json
  {
    "player_id": "...",
    "entity_id": "...",
    "type": "PASS"
  }
  ```
- **Intent**: Commit all changes and hand over control to the next character in the initiative queue.

### Step 5: State Synchronization
- **Action**: `GET /api/v1/game/{match_id}` (or wait for WebSocket `board.updated` event)
- **Intent**: Verify match state has been updated and observe the result of the actions.

## TECHNICAL INTERFACE
- **Related Specs:** `[[upsilonapi:api_battle_proxy]]`, `[[upsilonapi:api_websocket]]`
- **Code Tag:** `@spec-link [[us_api_flow_game_turn]]`

## EXPECTATION
- Action sequence results in correct state transition in the engine.
- Validation errors (422) are returned for illegal moves or skills.
- Turn cycle successfully transitions to the next entity after 'END_TURN'.
