# Logout Investigation: main vs release/aws

> Historical investigation note: this document captures a point-in-time comparison before the repository moved to the current `test/localdeploy`, `bhss`, and `release/aws-prod-candidate` branch model.

Date: 2026-04-15

Comparison branches:

- main: 324e23d14307a90b410ad5071833521f90c62cc4
- release/aws: 35dc12cce1d1e8e397bf97951cc98e3a18b1e67d

Current working branch: release/aws

## Objective

Investigate the UI logout mechanism end-to-end and identify branch differences that can change logout behavior.

## Scope

Included:

- UI logout trigger, API call, local state cleanup, redirect behavior.
- Backend revoke and auth validation path.
- Branch differences for logout/auth-critical files.

Excluded:

- Implementing fixes in this document.
- Non-logout features unless they affect token lifecycle.

## Phase 1 Completed: Baseline + Critical Diff Inventory

### Critical files changed between branches

- auth-service/docker-compose.dev.yml
- auth-service/src/auth/auth.service.ts
- auth-service/src/routes/index.ts
- bridge/src/api/auth.ts
- bridge/src/store/authStore.ts
- flowise-proxy-service-py/app/api/chat.py
- flowise-proxy-service-py/app/auth/middleware.py

### Relevant commits on release/aws (relative to main)

- 35dc12c fix: resolve 401 auth failures on AWS deployment
- 558cafa chore: sanitize sensitive values and update deployment/admin tooling
- 9c1f073 feat: teacher role, batch students, chat history viewer, token usage dashboard
- 486cb1f update

## Confirmed Code-Level Findings (So Far)

Automated evidence snapshot generated:

- docs/LOGOUT_BRANCH_EVIDENCE.md
- Source script: investigate_logout_diff.ps1

### Frontend logout path

File: bridge/src/api/auth.ts

- API base URL switched to API_BASE_URL import instead of inline env fallback.
- Error handling now prefers FastAPI detail field in addition to message.
- Logout endpoint path remains /api/v1/chat/revoke.

File: bridge/src/store/authStore.ts

- Role permissions expanded with teacher role.
- No confirmed logout endpoint change in this diff snippet.

Potential logout impact:

- Base URL centralization can alter runtime endpoint targeting across branches if config differs.

### Flowise proxy auth path

File: flowise-proxy-service-py/app/auth/middleware.py

- Added teacher role and elevated role grouping.
- Added dependency function require_elevated_role.

File: flowise-proxy-service-py/app/api/chat.py

- Permission checks now pass current user role into validate_user_permissions.

Potential logout impact:

- Role changes are likely access-control related, not direct logout changes, but can alter post-login behavior and perceived session validity.

### Auth service routes/config

File: auth-service/src/routes/index.ts

- Extensive admin and testing route changes.
- Import now includes requireAdminOrTeacher and NextFunction.
- Added production guard for testing routes via x-testing-token.

File: auth-service/src/auth/auth.service.ts

- adminCreateUser default skipVerification changed to true.

File: auth-service/docker-compose.dev.yml

- Mongo volume mapping changed from host path to named volume.

Potential logout impact:

- No direct logout endpoint path change confirmed in captured snippet, but route-level middleware and environment differences may affect auth/session behavior indirectly.

## Investigation Matrix (Execution Tracker)

| Check | main | release/aws | Evidence | Status |
| --- | --- | --- | --- | --- |
| Logout button triggers store logout | pending | pending | UI trace + console log | open |
| Logout request URL is correct | pending | pending | Network request | open |
| Authorization header included on revoke | pending | pending | Network request headers | open |
| Revoke response status and body | pending | pending | Network response | open |
| Local storage cleared | pending | pending | DevTools storage snapshot | open |
| Cookie state after logout | pending | pending | DevTools cookie snapshot | open |
| Redirect to login after logout | pending | pending | Browser route capture | open |
| Multi-tab logout behavior | pending | pending | Two-tab run notes | open |
| 401 -> refresh -> logout fallback | pending | pending | Network waterfall + logs | open |
| Server token invalidated after logout | pending | pending | DB/log evidence | open |

## Runtime Validation Commands

Run branch-specific tests with identical steps.

1. Capture branch and commit.

- git rev-parse --abbrev-ref HEAD
- git rev-parse HEAD

1. Record focused file diffs.

- git diff --name-only main...release/aws -- bridge/src/api/auth.ts bridge/src/store/authStore.ts flowise-proxy-service-py/app/api/chat.py flowise-proxy-service-py/app/auth/middleware.py auth-service/src/routes/index.ts auth-service/src/auth/auth.service.ts auth-service/docker-compose.dev.yml

1. Run browser logout flow and capture evidence.

- Open app, login, logout once.
- Save URL, request method/path, status code, and resulting route.

1. Run multi-tab test.

- Tab A login, Tab B same session, logout in Tab A.
- Record behavior in Tab B after action and refresh.

1. Run offline logout test.

- Disable network, click logout.
- Re-enable network and verify session cannot be resumed silently.

## Known Validation Gotcha

From repository memory:

- Refresh tokens are rotated immediately after successful refresh.
- Do not call /api/auth/refresh and /api/v1/chat/refresh sequentially with the same token during validation.

## Next Implementation Steps

1. Execute runtime matrix checks on release/aws first (current branch), then repeat on main.
1. Add pass/fail outcomes and root-cause notes directly in this document.
1. If mismatch is found, capture packet-level details for revoke/refresh requests and correlate with backend logs.
