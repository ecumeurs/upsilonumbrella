---
id: uc_player_registration
human_name: Player Registration Use Case
type: USER_STORY
layer: ARCHITECTURE
version: 1.0
status: STABLE
priority: 5
tags: []
parents:
  - [[upsilonbattleui:req_player_experience]]
dependents:
  - [[us_new_player_onboard]]
  - [[upsilonbattleui:ui_registration]]
---
# Player Registration Use Case

## INTENT
To allow a new user to enter the ecosystem by creating a persistent, game-agnostic account. Registration itself grants no game access and no character roster — those are established later, per game, through that game's own enrollment action.

## THE RULE / LOGIC
1. **Data Entry**: Guest provides mandatory registration data (`Account Name`, `Email`, `Password`). `Full Address` and `Birth Date` are optional fields with no current product use (per ISS-125) — the guest may leave them blank and the account is created with those fields null.
2. **Account Creation**: System validates data against security policies (`rule_password_policy`) and creates the account. The account is created game-agnostically: registration mints only the account record and an authentication token — it grants no game access and generates no character roster.
3. **Authentication**: System generates a JWT for the new session.
4. **Transition**: User is redirected to the **Game Selection** page (`ui_game_selection`), not the Dashboard. Character-roster generation and the reroll flow happen later, as part of a game's own enrollment action, not as part of registration.

## TECHNICAL INTERFACE (The Bridge)
- **Code Tag:** `@spec-link [[uc_player_registration]]`

## EXPECTATION (For Testing)
- Submission of valid form -> Account + JWT created -> Success leads to redirection to the Game Selection page, not the Dashboard.
- No character roster exists on the account immediately after registration; the account has zero game grants.
- No personal data (like Email) is collected per `us_new_player_onboard`.
