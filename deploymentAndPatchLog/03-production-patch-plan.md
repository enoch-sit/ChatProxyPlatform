# Production Patch Plan

This plan assumes you want a comprehensive understanding first and no production mutation yet.

## Decision summary

Do not patch production directly from the current `release/aws` branch state until the intended production scope is narrowed and the dev `flowise-proxy` runtime errors are explained.

## Phase 1 - Freeze the candidate patch set

Goal: decide exactly what production is meant to receive.

1. Separate intended prod changes from everything else on `release/aws`.
2. Confirm whether prod should include only:
   - `flowise-proxy-service-py/**`
   - `bridge/**`
   - `version.json`
3. Exclude or defer unrelated areas unless they are explicitly part of the prod change:
   - `auth-service/**`
   - `accounting-service/**`
   - `infra/**`
   - workstation and fleet scripts
   - local deployment helpers
4. Remove ambiguity from the two untracked files before rollout:
   - `infra/scripts/audit-ecs-status.ps1`
   - `scripts/update_aws_secret.py`

Exit criterion:

- You can name the exact files and services intended for prod.

## Phase 2 - Rebuild trust in the promotion source

Goal: prove the selected changes are safe enough to promote.

1. Investigate why dev `flowise-proxy` shows `recent-errors:4`.
2. Decide whether those errors are:
   - historical noise unrelated to current code
   - already fixed in `release/aws`
   - still present and a blocker for prod
3. Re-run the dev audit after that investigation.
4. If the patch changes both services, validate `flowise-proxy` behavior first and `bridge` behavior second.

Exit criterion:

- Dev is either clean, or you have a written reason why the prod patch is still safe despite the dev error signal.

## Phase 3 - Lock the prod release intent

Goal: create a specific promotion target instead of relying on branch ambiguity.

Recommended options:

1. Preferred: create a narrow release commit or branch that contains only the intended prod changes.
2. Acceptable: keep `release/aws`, but do a final diff review against `main` and explicitly sign off on every changed file that could influence the selected service build or deploy behavior.

Before dispatch:

1. Confirm `version.json` has the intended version bumps for the services you will deploy.
2. Record the currently deployed prod image tags and task definitions.
3. Record the target commit SHA you intend to promote.
4. Confirm the workflow dispatch will run from that exact branch/ref.

Exit criterion:

- There is no doubt which ref, which services, and which version tags are going to prod.

## Phase 4 - Pre-deploy prod checks

Run these before any mutation:

1. `audit-ecs-status.ps1 -Environment prod -AsJson`
2. `aws secretsmanager describe-secret --secret-id /chatproxy/prod/flowise/api-key --region us-east-1`
3. CloudWatch log spot check for:
   - `/ecs/chatproxy-prod-flowise-proxy`
   - `/ecs/chatproxy-prod-bridge`
4. Confirm ECS services are all `desired == running`.
5. Confirm ALB target groups are healthy.

Exit criterion:

- Prod baseline is healthy and recorded before mutation.

## Phase 5 - Controlled production rollout

Recommended order:

1. Dispatch `Deploy Prod` for `flowise-proxy` from the approved ref.
2. Wait for ECS stability.
3. Validate:
   - admin sign-in still works
   - admin settings page loads
   - Flowise API key status loads
   - Flowise API key test path works
   - key update path works if that is part of the change
4. Only after backend validation passes, dispatch `Deploy Prod` for `bridge`.
5. Wait for ECS stability.
6. Re-run UI smoke validation.

## Phase 6 - Immediate rollback rules

Use `rollback.yml` if any of these happen:

- ECS will not stabilize
- target health degrades
- admin settings page breaks after rollout
- proxy runtime endpoints regress
- bridge works but backend behavior is wrong

Rollback order:

1. `bridge` if the issue is UI-only and backend remains good
2. `flowise-proxy` first if backend behavior regressed

## Recommended go or no-go based on current evidence

### No-go conditions right now

- You cannot clearly explain the dev `flowise-proxy` errors.
- You cannot prove the exact prod patch scope from `release/aws`.
- You intend to promote only UI/proxy changes but leave broad branch drift unresolved.

### Go conditions

- Patch scope narrowed and reviewed.
- Dev error signal investigated.
- Prod baseline captured.
- Secret presence confirmed.
- Rollback path ready.

## Practical recommendation

If you want the safest next step, do not patch prod yet. First produce a narrowed candidate ref for `flowise-proxy` and `bridge`, re-check dev logs for `flowise-proxy`, and then dispatch `Deploy Prod` service by service from that exact ref.