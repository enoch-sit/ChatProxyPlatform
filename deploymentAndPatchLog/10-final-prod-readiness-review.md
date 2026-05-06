# Final Prod Readiness Review

## Review target

- Branch: `release/aws-prod-candidate`
- Commit: `d8edea2`

## Primary finding

The narrowed candidate does not provide a clear code-level fix for the dev `flowise-proxy` scheduled chatflow sync `401 Unauthorized` issue.

## Evidence

### 1. The dev error is specific and repeatable

From earlier CloudWatch review:

- scheduled sync calls `GET https://flowise.aidcec-ai-agent.com/api/v1/chatflows`
- Flowise responds with `401 Unauthorized`
- health checks still return `200 OK`

This is an authorization/key-resolution problem, not an ECS availability problem.

### 1b. Production now shows the same failure pattern

The fresh production baseline on `2026-05-04T03:09:22Z` showed:

- `flowise-proxy` ECS service still stable and target healthy
- recent log signal `recent-errors:4`
- repeated scheduled sync calls to `GET https://flowise.aidcec-ai-agent.com/api/v1/chatflows`
- `401 Unauthorized` responses in `/ecs/chatproxy-prod-flowise-proxy`

This reduces confidence further because the unresolved auth problem is not confined to dev.

### 2. The runtime key resolution path used by sync is unchanged

The service responsible for adding the Flowise `Authorization` header during sync is:

- `flowise-proxy-service-py/app/services/flowise_service.py`

That file resolves the API key from runtime settings with `.env` fallback and builds the request headers. It is not part of the committed candidate diff.

### 3. The committed proxy changes are adjacent, not curative

The candidate does include meaningful proxy changes, including:

- admin endpoints for Flowise API key status and testing
- user/chatflow assignment changes
- admin chat history additions
- query and sync-safety improvements in chatflow handling

However, the reviewed changes in:

- `flowise-proxy-service-py/app/api/admin.py`
- `flowise-proxy-service-py/app/services/chatflow_service.py`
- `flowise-proxy-service-py/app/api/chatflows.py`

do not show a direct modification to the key-resolution logic used by the scheduled sync task.

## Consequence

Commit `d8edea2` should not be treated as a demonstrated fix for the dev Flowise `401` problem.

At best, it improves operational visibility and runtime management around the key. It does not, on the evidence reviewed, prove that the scheduled sync will authenticate successfully after promotion.

## Readiness outcome

### What is ready

- patch scope is narrowed and committed
- production workflow and prod Terraform surfaces are included
- versioning is explicit at `1.0.1` for `bridge` and `flowise-proxy`
- `auth-service` and `accounting-service` spillover has been excluded

### What is not fully ready

- the dev Flowise auth/sync issue remains unresolved at the code-evidence level

## Recommendation

### Strict recommendation

Do not promote additional `flowise-proxy` changes to prod until one of these is true:

1. You verify in dev that the new admin key status/test/update flow results in a successful scheduled or manual chatflow sync.
2. You identify and correct the environment/config cause for the `401` in both dev and prod.

### Conditional promotion recommendation

Promotion can still be reasonable if all of the following are true:

1. You accept that `d8edea2` does not itself prove a sync auth fix.
2. The production change is still valuable for admin visibility and runtime key management.
3. You are intentionally using the new runtime key management surface to correct the already-existing prod auth problem during validation.
4. You are prepared to rollback quickly with the updated rollback workflow if proxy behavior regresses.

## Decision summary

- Scope readiness: yes
- Versioning readiness: yes
- Operational rollback readiness: yes
- Evidence of fixing dev sync `401`: no
- Evidence that prod is currently clean: no
- Unconditional prod go recommendation: no
- Conditional prod go recommendation with explicit risk acceptance: yes