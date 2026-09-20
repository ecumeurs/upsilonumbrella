# Issues Prioritisation Audit

**Audit date:** 2026-09-02  
**Scope:** All 42 currently active issue files from `ISS-001` through `ISS-141`.

Historical resolved issues are intentionally deleted per `issues/README.md` and were not treated as active. Eight investigators covered the code, tests, documentation, and history by subsystem, followed by an independent reviewer verdict of `OKAY`.

## Executive Result

- No issue currently warrants `P0`.
- 7 issues should be `P1`, 19 should be `P2`, and 16 should be `P3`.
- 8 active files are fixed, obsolete, or superseded and should be closed.
- 17 issues are only partially valid because their original diagnosis or scope is stale.
- The biggest consolidation opportunities are deterministic battle fixtures, board generation, raw CLI requests, and decomposition of the `ISS-139` umbrella.
- No files were modified during the audit; the worktree remained clean.

## Priority Matrix

Validity values are `Valid`, `Partial`, `Resolved`, `Obsolete`, or `Decision`.

| Issue | Validity | Impact | Priority | Recommended disposition |
|---|---|---:|---:|---|
| ISS-049 | Valid modernization | Low | P3 | Rewrite as optional actor-generics RFC; not a live defect |
| ISS-055 | Valid | Medium | P2 | Keep; narrow to actor dispatch/ack/reply integrity |
| ISS-072 | Valid feature | Low | P2 | Update stale API/UI references; retain independently |
| ISS-077 | Partial | Low | P3 | Split; close delivered inspection, retain telemetry/detail work |
| ISS-078 | Valid | Medium | P1 | Keep; implement shield provenance and mitigation credit after ISS-146 |
| ISS-079 | Partial | Low | P3 | Close indexing defect; separate optional Y-major contract migration |
| ISS-080 | Partial | Medium | P2 | Split error-key taxonomy from envelope-placement decision |
| ISS-081 | Partial | Medium | P2 | Rewrite for current Go services; depend on ISS-080 |
| ISS-082 | Partial | Medium | P2 | Close old scaffolding scope; create focused hosted-Playwright-CI issue |
| ISS-087 | Partial | Medium | P2 | Remove completed size/obstacle claims; retain terrain/preset work |
| ISS-089 | Decision | Low | P3 | Fold into future market/vendor design or close as obsolete scope |
| ISS-090 | Valid | Medium | P2 | Split unknown-action rejection from endpoint-segregation architecture |
| ISS-100 | Partial | Low | P2 | Revalidate current devcontainer/GitHub WebGL capability |
| ISS-103 | Resolved | Low | P3 | Close; foe-loadout masking is implemented and tested |
| ISS-104 | Resolved | Low | P3 | Close; queue claim is transactionally serialized |
| ISS-105 | Partial | Low | P3 | Decide whether direct farms longer than 15 minutes are supported |
| ISS-106 | Partial | High | P1 | Close PHP/false-`matched` parts; retain failed-start compensation |
| ISS-107 | Resolved | Low | P3 | Close completed edge-suite audit |
| ISS-108 | Valid test gap | Medium | P2 | Merge deterministic-board seam into shared fixture issue |
| ISS-109 | Valid test/docs gap | Medium | P2 | Merge fixture work; separately correct stale movement atom |
| ISS-110 | Decision | Medium | P2 | Split deterministic initiative from human-first gameplay decision |
| ISS-111 | Resolved | Low | P3 | Close; cooldown decrement and regression tests exist |
| ISS-112 | Partial | Low | P3 | Close or merge with ISS-115 if raw CLI calls are desired |
| ISS-113 | Resolved | Low | P3 | Close; reroll post-match gate exists and is tested |
| ISS-114 | Valid | Medium | P2 | Keep; teardown slot still overwrites previous bot cleanup |
| ISS-115 | Partial | Low | P3 | Close or merge with ISS-112 as raw-request capability |
| ISS-116 | Partial | Medium | P1 | Keep; update ownership to upsilonauth and drop stale anonymize claim |
| ISS-117 | Partial | Medium | P2 | Close historical Dependabot incident; retain workspace scanning work |
| ISS-118 | Valid | High | P1 | Keep; update as active post-cutover GDPR compliance gap |
| ISS-119 | Resolved | Low | P3 | Run four targeted scenarios, then close |
| ISS-122 | Obsolete | Low | P3 | Close as superseded by explicit game-selection flow |
| ISS-123 | Partial | Medium | P2 | Narrow to stale host seed scripts and callers |
| ISS-124 | Resolved | Low | P3 | Close; enrollment/game-selection implementation and tests landed |
| ISS-125 | Decision | Medium | P1 | Settle optional-vs-removal PII policy, then update ATD/API/UI |
| ISS-127 | Valid | Medium | P2 | Keep; still 13 links/12 distinct atoms against the cap of 10 |
| ISS-128 | Valid | Medium | P2 | Keep; checker still uses naive whole-file substring matching |
| ISS-129 | Partial | Medium | P2 | Split policy contradiction from repository-wide remediation |
| ISS-133 | Decision | Low | P3 | Retain only as serializer ownership/boundary decision |
| ISS-134 | Valid | High | P1 | Keep; standalone module manifests demonstrably fail resolution |
| ISS-136 | Partial | Medium | P2 | Rewrite around broken retry cleanup and RNG-sensitive probe |
| ISS-137 | Valid | Medium | P1 | Keep; logout can leave a renewal replacement token active |
| ISS-139 | Partial | Medium | P2 | Decompose into atomic documentation/tooling issues, then close umbrella |

## Recommended P1 Order

1. `ISS-118` - GDPR export returns success while omitting game/economy personal data; the current placeholder is visible at `upsilonauth/internal/gateway/auth.go:200`.
2. `ISS-106` - engine-start failures can leave match and queue state behind at `upsilonhub/internal/games/battle/matchmaking.go:363`.
3. `ISS-137` - renewal occurs before logout and only the old credential is revoked; see `upsilonauth/internal/gateway/middleware/auth.go:59`.
4. `ISS-134` - auth, economy, and hub no longer resolve independently from committed manifests; workspace and Docker builds mask the drift.
5. `ISS-116` - admin listings still serialize address and birth date through `upsilonauth/internal/gateway/internal.go:55`.
6. `ISS-125` - settle and execute removal or optionalization of unnecessary registration PII; the current requirement remains in `upsilonauth/internal/gateway/auth.go:267`.
7. `ISS-078` - contracted shield-mitigation rewards are not emitted; sequence after shield semantics in `ISS-146`.

## Consolidation Plan

- **Create one deterministic battle-fixture issue:** merge the testability portions of `ISS-108`, `ISS-109`, and `ISS-110`. It should provide production-valid deterministic map, spawn, height, and initiative controls, not test-only branches.
- **Consolidate board-generation policy:** merge the remaining product portion of `ISS-108` into `ISS-087`, covering terrain presets, obstacle density, spawn-aware guarantees, and map quality.
- **Conditionally merge `ISS-112` and `ISS-115`:** both reduce to a caller-controlled raw CLI request primitive. If low-level transport E2E is not a supported CLI responsibility, close both instead.
- **Close `ISS-122` and `ISS-124`:** they describe the same historical onboarding failure; the explicit `/games` enrollment flow resolves both.
- **Split `ISS-139`:** extract wrong semantic tags, missing atom expectations, auth-cache contract drift, SSE atom ownership, CONTRACT-link policy, and external `atd check` matching. The current umbrella hides unrelated ownership and governance decisions.
- **Do not merge:** keep `ISS-080` -> `ISS-081`, `ISS-078` -> `ISS-146`, `ISS-116`/`ISS-118`/`ISS-125`, `ISS-133`/`ISS-134`, and `ISS-072`/`ISS-090` distinct because they have different root causes and completion boundaries.

## Verification

- Targeted tests passed for cooldowns, reroll gating, matchmaking queue poisoning, foe-loadout masking, actor/message queues, CLI helpers, and request-ID middleware.
- `govulncheck ./...` found zero currently called vulnerabilities in `upsilonapi`; GitHub reported zero open Dependabot alerts, although workspace scanning remains absent.
- Read-only standalone Go checks confirmed `ISS-134`: auth, economy, and hub manifests do not resolve cleanly outside the umbrella workspace.
- Playwright discovery found 63 tests, but no live browser stack was started; `ISS-100` and the runtime confirmation for `ISS-119` therefore retain explicit verification debt.

## Audit Notes

- `ISS-103`, `ISS-104`, `ISS-107`, `ISS-111`, `ISS-113`, and `ISS-124` are resolved in code.
- `ISS-122` is obsolete because the explicit game-selection flow supersedes it.
- `ISS-119` is resolved in code but should receive its four targeted runtime checks before closure.
- Several issues mix product behavior, testability, and architecture work. Those dimensions should be split before implementation so priority reflects the actual completion boundary.
- The review found no supported reason to merge distinct security concerns (`ISS-116`, `ISS-118`, `ISS-125`) or distinct dependency concerns (`ISS-117`, `ISS-133`, `ISS-134`).
