# Login Logout Investigation: release/aws vs fix/remote-login-proxy-url

Date: 2026-04-15

Branches:

- release/aws: 35dc12cce1d1e8e397bf97951cc98e3a18b1e67d
- fix/remote-login-proxy-url: cfe464535297f3f3d53693e2b439bec163cc7252

Current working branch during setup: release/aws

## Goal

Investigate intermittent logout behavior where the UI does not navigate to the login page, and validate login/logout flow consistency across both branches.

## Implemented Baseline Artifacts

- Evidence report: docs/LOGIN_LOGOUT_BRANCH_EVIDENCE_release_aws_vs_fix_remote_login_proxy_url.md
- Evidence generator script: investigate_logout_diff.ps1

## Static Diff Result Summary

High-signal changed files between the two branches:

- bridge/src/api/auth.ts
- bridge/src/api/config.ts

Notable behavioral drift:

- Error parsing in auth API calls differs.
- release/aws checks FastAPI detail first: detail || message.
- fix/remote-login-proxy-url checks message only.
- Logout/refresh endpoint paths remain the same in both branches:
  - /api/v1/chat/authenticate
  - /api/v1/chat/refresh
  - /api/v1/chat/revoke

Initial inference:

- Non-redirect logout is unlikely caused by endpoint path differences.
- It is more likely tied to client-side state/route update timing, failed refresh fallback handling, or runtime environment/base URL behavior.

## End-to-End Investigation Matrix

| Scenario | release/aws | fix/remote-login-proxy-url | Evidence required | Status |
| --- | --- | --- | --- | --- |
| Login success redirects to dashboard/chat | pending | pending | Network + route capture | open |
| Manual logout redirects to login | pending | pending | Click trace + route capture | open |
| Logout with revoke 5xx still redirects to login | pending | pending | Simulated failure + route capture | open |
| 401 interceptor fallback logout redirects to login | pending | pending | 401 chain + route capture | open |
| Multi-tab logout propagates to second tab | pending | pending | Two-tab notes + refresh result | open |
| Visibility change + token refresh does not mask logout state | pending | pending | Timeline + logs | open |
| Post-logout local storage and auth state are cleared | pending | pending | Storage snapshot | open |
| Post-logout token cannot silently restore session on reload | pending | pending | Reload behavior + network | open |

## Runtime Execution Steps

1. Release/aws branch run.

- Verify current branch and SHA.
- Start UI and services for this branch.
- Run scenarios in matrix order and capture artifacts.

1. Fix/remote-login-proxy-url branch run.

- Checkout branch and verify SHA.
- Start UI and services for this branch.
- Re-run the exact same scenario order and capture artifacts.

1. Compare outcomes.

- Mark pass/fail row-by-row.
- Identify branch-only failures and classify root cause.

## Evidence Collection Standard

For each scenario row, capture all items below.

- Browser route before and after event.
- Relevant request URL, status code, and response body for authenticate, refresh, revoke.
- Auth store state snapshot: isAuthenticated, user, tokens.
- localStorage keys for access and refresh tokens.
- Cookie state if applicable.
- Backend log snippets correlated by timestamp.

## Debug Focus for Non-Redirect Logout

Target these checkpoints first.

1. Verify logout action is followed by ProtectedRoute re-evaluation.
1. Verify no stale component tree keeps protected layout mounted after auth state clear.
1. Verify interceptor-driven logout path behaves the same as button-driven logout.
1. Verify branch runtime API base URL resolves correctly in built frontend.
1. Verify refresh failure path cannot rehydrate stale auth state after local cleanup.

## Recommended Instrumentation

Add temporary logs while executing scenarios if issue is intermittent.

- In bridge/src/store/authStore.ts: log start/end of logout and refresh, plus resulting state.
- In bridge/src/components/auth/ProtectedRoute.tsx: log each guard evaluation and decision.
- In bridge/src/api/client.ts: log interceptor 401 flow and retry/logout decisions.

## Deliverables After Runtime Execution

1. Completed matrix with pass/fail and linked artifacts.
1. Root-cause shortlist ranked by confidence.
1. Minimal fix proposal plus regression checklist for login/logout redirect behavior.
