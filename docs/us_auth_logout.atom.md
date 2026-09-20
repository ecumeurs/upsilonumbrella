---
id: us_auth_logout
human_name: "Secure Logout User Story"
type: USER_STORY
layer: BUSINESS
version: 1.0
status: STABLE
priority: 3
tags: [auth, logout, experience]
parents:
  - [[req_admin_experience]]
  - [[upsilonbattleui:req_player_experience]]
dependents:
  - [[uc_auth_logout]]
  - [[upsilonauth:mech_token_revocation_cascade]]
---

# Secure Logout User Story

## INTENT
As a user (Player or Administrator), I want to securely log out of the system so that my session is terminated and no unauthorized access can occur from the same device.

## THE RULE / LOGIC
1. **Trigger**: User clicks the "Logout" button in the navigation header.
2. **Confirmation**: Optional confirmation modal (if required by UI design).
3. **Session Purge**: Active session token is invalidated on the server.
4. **Redirection**: User is returned to the landing page or login screen to prevent cache-based access.

## TECHNICAL INTERFACE (The Bridge)
- **Code Tag:** `@spec-link [[us_auth_logout]]`
- **UI Component:** `Header.vue` or `AppMenu.vue`
- **Dependencies:** [[upsilonapi:api_auth_logout]]

## EXPECTATION (For Testing)
1. User session state is cleared from the logic layer (Vuex/Pinia).
2. The user can no longer access protected routes after logout.
3. The server rejects subsequent requests with the old token.
