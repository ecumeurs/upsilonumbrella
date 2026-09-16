---
id: req_security
human_name: Sanctum Token Security Requirement
type: REQUIREMENT
layer: BUSINESS
version: 1.1
status: STABLE
priority: 5
tags: [auth, sanctum]
parents:
  - [[shared:req_tech_debt_backlog]]
dependents:
  - [[req_security_token_ttl]]
  - [[uc_auth_logout]]
  - [[upsilonapi:rule_admin_access_restriction]]
  - [[upsilonapi:rule_password_policy]]
---
# Sanctum Token Security Requirement

## INTENT
All non-public requests must carry a valid Sanctum bearer token over HTTPS, with login and registration the only token-issuing public entry points.

## THE RULE / LOGIC
Ensures all non-public requests to the application are authenticated and secure. Acceptance criteria:
- **Encryption:** All traffic MUST use HTTPS (self-signed certificates allowed for development/light environments).
- **Authentication:** Every UI page (dashboard, waiting room, board) and all backend API calls require a valid Laravel Sanctum Personal Access Token sent as a Bearer token in the `Authorization` header.
- **Public exemptions:** The Landing Page, User Registration (`POST /v1/auth/register`) and User Login (`POST /v1/auth/login`) are fully exempt from authorization.
- **Token issuance:** A successful login or registration immediately issues a Sanctum token to the client.
- Token lifetime and renewal are governed separately by [[req_security_token_ttl]].

## TECHNICAL INTERFACE (The Bridge)
- **Code Tag:** `@spec-link [[req_security]]`
