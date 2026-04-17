# Runtime Results: release/aws vs fix/remote-login-proxy-url

Date: 2026-04-15

## Environment Snapshot

| Item | release/aws | fix/remote-login-proxy-url |
| --- | --- | --- |
| Commit SHA | 35dc12cce1d1e8e397bf97951cc98e3a18b1e67d | cfe464535297f3f3d53693e2b439bec163cc7252 |
| Frontend API base URL at runtime | pending | pending |
| Auth service URL at runtime | pending | pending |
| Proxy service URL at runtime | pending | pending |
| Browser and version | pending | pending |

## Scenario Results

| Scenario ID | Scenario | release/aws result | fix/remote-login-proxy-url result | Branch difference | Evidence path | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | Login success redirects to protected page | pending | pending | pending | pending | |
| S2 | Manual logout redirects to /login | pending | pending | pending | pending | |
| S3 | Logout with revoke failure still redirects to /login | pending | pending | pending | pending | |
| S4 | 401 interceptor fallback logout redirects to /login | pending | pending | pending | pending | |
| S5 | Multi-tab logout propagation | pending | pending | pending | pending | |
| S6 | Visibility change does not break logout redirect | pending | pending | pending | pending | |
| S7 | Post-logout storage clear | pending | pending | pending | pending | |
| S8 | Reload after logout does not restore session | pending | pending | pending | pending | |

## Failure Trace Log

| Failure ID | Branch | Trigger point | Observed behavior | Expected behavior | Suspected component | Evidence path |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | pending | pending | pending | pending | pending | pending |

## Root Cause Ranking

| Rank | Hypothesis | Confidence | Evidence | Affects branch |
| --- | --- | --- | --- | --- |
| 1 | pending | pending | pending | pending |
| 2 | pending | pending | pending | pending |
| 3 | pending | pending | pending | pending |

## Proposed Fix Candidates

1. pending
1. pending
1. pending

## Regression Checklist

1. Manual logout from protected page always lands on /login.
1. Interceptor-triggered logout always lands on /login.
1. No stale auth restoration after reload.
1. Multi-tab session consistency preserved.
1. Same behavior confirmed in both branches after patch.
