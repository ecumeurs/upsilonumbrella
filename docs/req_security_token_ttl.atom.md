---
id: req_security_token_ttl
human_name: Token TTL Requirement
type: REQUIREMENT
layer: BUSINESS
version: 1.0
status: STABLE
priority: 5
tags: [auth, sanctum, security]
parents:
  - [[req_security]]
dependents:
  - [[upsilonauth:mech_sanctum_token_renewal]]
  - [[upsilonbattleui:mechanic_frontend_auth_bridge]]
  - [[upsilonbattleui:req_ui_session_timeout]]
---
# Token TTL Requirement

## INTENT
Ensure tokens have a limited lifespan to mitigate risk of compromised tokens.

## THE RULE / LOGIC
- Personal Access Tokens must have a 15-minute Time-To-Live (TTL).
- **Renewal Window:** If a token is older than 10 minutes but not yet expired, a new token MUST be issued upon the next request.
- **Grace Period:** The old token remains valid for exactly 20 seconds after the new token is issued to ensure inflight requests complete.
- **Delivery:** The new token MUST be returned in the standard JSON envelope under `meta.token`, with `meta.message` set to "Token renewed".
- **Accounting:** Only one renewal should occur per window; subsequent requests using the old token during the grace period should not trigger further renewals.

## TECHNICAL INTERFACE (The Bridge)
- **Code Tag:** `@spec-link [[req_security_token_ttl]]`
- **Related Issue:** `ISS-021`

## EXPECTATION (For Testing)
- If a token is older than 15 minutes, requests return 401 Unauthorized.
- If a token is between 10 and 15 minutes old, the response contains a new token in `meta.token`.
- After a new token is issued, the old token becomes invalid after exactly 20 seconds.
- Requests using the old token during the 20-second grace period MUST NOT trigger a second renewal.
