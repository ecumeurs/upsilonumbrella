---
id: requirement_customer_player_profile
status: STABLE
human_name: Player Meta-game Management
type: REQUIREMENT
layer: BUSINESS
priority: 3
tags: [profile, game-metadata, characters]
parents: []
version: 1.0
dependents:
  - [[rule_progression]]
  - [[upsilonapi:api_profile_credits]]
  - [[upsilonapi:rule_character_renaming]]
  - [[upsilontypes:entity_character]]
---

# Player Meta-game Management

## INTENT
To define the requirements for managing player-specific game metadata, such as character rosters and career progression.

## THE RULE / LOGIC
- Players can view their character rosters and individual character stats.
- Career win/loss records are displayed as part of the player's tactical identity.
- Future expansions will include achievements and competitive rankings.

## TECHNICAL INTERFACE
- **Controller:** `ProfileController`
- **Code Tag:** `@spec-link [[requirement_customer_player_profile]]`
- **Endpoints:** `GET /api/v1/profile/characters`, `GET /api/v1/profile`

## EXPECTATION
