# Current Status

## Post-remediation update

- Follow-up date: `2026-05-04`
- Branch deployed: `release/aws-prod-candidate`
- Deployed commit: `d8edea2`
- Production `flowise-proxy` live image: `168437900315.dkr.ecr.us-east-1.amazonaws.com/chatproxy/flowise-proxy:v1.0.1-d8edea2`
- Production `bridge` live image: `168437900315.dkr.ecr.us-east-1.amazonaws.com/chatproxy/bridge:v1.0.1-d8edea2`
- Production `bridge` live task definition: `chatproxy-prod-bridge:2`
- Production Flowise admin validation after runtime key re-entry:
  - key source: `runtime`
  - key test: `200`
  - manual sync result: `total_fetched=1`, `updated=1`, `deleted=0`, `errors=0`
- Production bridge smoke check after deploy: `https://aidcec-ai-agent.com` returned HTTP `200`

Interpretation:

- The earlier production Flowise auth failure was resolved by re-entering the runtime key.
- The originally pending `bridge` rollout is now complete.
- Current production status for the candidate scope is recovered backend plus deployed frontend, not partial rollout.

## Audit context

- Audit date: `2026-05-04`
- Machine: local Windows workstation
- Branch checked out: `release/aws`
- Current local HEAD: `f9cc0d3`
- AWS CLI identity: `arn:aws:iam::168437900315:user/chatproxy-admin`
- Region used by workflows and audit: `us-east-1`

## Local git state relevant to a prod patch

- Current branch is already `release/aws`.
- Untracked files were present during the review:
  - `infra/scripts/audit-ecs-status.ps1`
  - `scripts/update_aws_secret.py`
- Branch delta versus `main` is broad. It includes:
  - `bridge/**`
  - `flowise-proxy-service-py/**`
  - `auth-service/**`
  - `accounting-service/**`
  - `infra/**`
  - `local-deploy.py`
  - workstation and fleet scripts

Interpretation:

- `release/aws` is not currently a narrowly isolated AWS UI/proxy patch branch.
- If production should only receive `bridge` and `flowise-proxy` changes, the patch set needs explicit scoping before dispatching `Deploy Prod`.

## Production AWS status

Source: read-only execution of `infra/scripts/audit-ecs-status.ps1 -Environment prod -AsJson`

| Service | ECS health | Image state | Notes |
| --- | --- | --- | --- |
| `auth-service` | Healthy, `1/1`, rollout `COMPLETED` | Current | Live image matches terraform and latest ECR seen by audit. |
| `accounting-service` | Healthy, `1/1`, rollout `COMPLETED` | Current | Still pinned to `latest`, which is operationally weaker than immutable version tags. |
| `flowise-proxy` | ECS stable, target healthy | Historical note | Original audit snapshot only. Follow-up remediation moved prod to `v1.0.1-d8edea2` and restored runtime-key-backed sync behavior. |
| `bridge` | Healthy, `1/1`, rollout `COMPLETED` | Historical note | Original audit snapshot only. Follow-up remediation moved prod to `v1.0.1-d8edea2` and task definition `chatproxy-prod-bridge:2`. |

### Production image details seen in the audit

- `auth-service`: `v1.0.0-b7d1ef7`
- `flowise-proxy`: `v1.0.0-b7d1ef7`
- `bridge`: `v1.0.0-b7d1ef7`
- `accounting-service`: `latest`

### Production operational interpretation

- Production remains ECS-stable enough for investigation and controlled rollout.
- Production is not fully aligned with the newest pushed images for `flowise-proxy` and `bridge`.
- `flowise-proxy` is currently showing the same scheduled Flowise auth failure pattern seen in dev: periodic sync attempts return `401 Unauthorized` while health checks stay green.
- That makes the controlling production risk more specific than a platform outage: the current runtime key or auth path is not clean even before promotion.
- The image gap is still useful because it shows a clear difference between what has been built and what has been promoted.
- That gap is also a risk: a careless prod dispatch could promote code that has not been explicitly approved.

## Dev AWS status

Source: read-only execution of `infra/scripts/audit-ecs-status.ps1 -Environment dev -AsJson`

| Service | ECS health | Image state | Notes |
| --- | --- | --- | --- |
| `auth-service` | Healthy, `1/1`, rollout `COMPLETED` | Current | No issue flagged by the audit. |
| `accounting-service` | Healthy, `1/1`, rollout `COMPLETED` | Current | No issue flagged by the audit. |
| `flowise-proxy` | ECS stable, target healthy | Unhealthy runtime signal | Audit reported `recent-errors:4`. |
| `bridge` | Healthy, `1/1`, rollout `COMPLETED` | Current | No issue flagged by the audit. |

### Dev operational interpretation

- Dev is not a clean green baseline for promotion because `flowise-proxy` has recent runtime errors.
- Before prod rollout, inspect those dev errors and decide whether they are expected noise, already fixed on `release/aws`, or evidence of an unresolved regression.

## Secrets and logging surfaces

- Production Flowise fallback secret exists:
  - Secret name: `/chatproxy/prod/flowise/api-key`
  - Tags confirm `Project=chatproxy` and `Environment=prod`
- Production CloudWatch log groups discovered:
  - `/ecs/chatproxy-prod-accounting`
  - `/ecs/chatproxy-prod-auth`
  - `/ecs/chatproxy-prod-bridge`
  - `/ecs/chatproxy-prod-flowise`
  - `/ecs/chatproxy-prod-flowise-proxy`

## Bottom line before patching prod

- Green enough to continue planning: yes.
- Green enough to patch prod immediately without narrowing scope first: no.
- Green enough to treat production as a clean baseline: no.

The controlling risks are now both branch scope and the already-active Flowise sync auth failure in production.