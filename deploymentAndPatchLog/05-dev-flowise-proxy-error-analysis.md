# Dev Flowise Proxy Error Analysis

## Question answered

Why did the dev ECS audit mark `flowise-proxy` as unhealthy even though ECS service stability and target health were green?

## Evidence reviewed

- CloudWatch log group: `/ecs/chatproxy-dev-flowise-proxy`
- Time window checked: last 2 hours during this review
- Audit symptom: `LogSignal = recent-errors:4`

## What the logs show

The error signal is not a crash loop and not a health-check failure.

The container remains healthy throughout the sampled window:

- repeated `GET /health` requests return `200 OK`
- the service stays on a single running task
- ECS target health remains healthy

The repeated errors are from scheduled chatflow synchronization:

- `Starting scheduled chatflow sync`
- `GET https://flowise.aidcec-ai-agent.com/api/v1/chatflows` returns `401 Unauthorized`
- `Flowise API returned HTTP 401: {"error":"Unauthorized Access"}`
- `Failed to fetch chatflows from Flowise API`
- sync completes with `0 added, 0 updated, 0 deleted`

## Working interpretation

The current dev unhealthy signal is a credential or authorization problem between `flowise-proxy` and the Flowise API endpoint, not a platform availability problem.

Most likely classes of cause:

1. The Flowise API key available to dev `flowise-proxy` is missing, stale, or rejected.
2. Runtime key state and fallback startup secret are out of sync.
3. The target Flowise endpoint now enforces auth in a way the scheduled sync path is not satisfying.

## Why this matters for prod

This does not automatically mean production is broken.

It does mean:

- dev is not a clean promotion baseline for `flowise-proxy`
- if the prod patch affects chatflow sync or Flowise auth handling, this is a release blocker until explained
- if the prod patch is unrelated to chatflow sync auth, this is still a caution item that should be called out before promotion

## Release decision impact

### Safe conclusion

Do not treat dev as fully green today.

### More precise conclusion

You can still consider a prod rollout only after deciding one of these is true:

1. The `401 Unauthorized` sync issue is already fixed in the exact ref you intend to promote.
2. The prod patch does not touch the failing auth/sync path and the issue is environmental to dev only.
3. You intentionally accept the dev auth drift and have a rollback-ready prod rollout plan.

## Suggested follow-up checks

1. Compare the configured Flowise API key source for dev against the current Secrets Manager value.
2. Validate the admin settings key status and key test endpoints in dev.
3. Check whether the `release/aws` changes in `flowise-proxy-service-py` alter chatflow sync auth handling.

## Bottom line

The current dev `flowise-proxy` issue is a repeated Flowise authorization failure during scheduled chatflow sync, not an ECS availability failure. That makes it narrower and more diagnosable, but it is still unresolved release risk until explained.