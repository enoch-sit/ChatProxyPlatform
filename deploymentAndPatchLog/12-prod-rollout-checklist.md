# Prod Rollout Checklist

## Execution result

- Executed on: `2026-05-04`
- Branch used: `release/aws-prod-candidate`
- Commit used: `d8edea2`
- `flowise-proxy` result: deployed to `v1.0.1-d8edea2`
- `bridge` result: deployed to `v1.0.1-d8edea2`
- Production backend validation after runtime key re-entry:
  - Flowise key source: `runtime`
  - Flowise key test: `200`
  - Manual sync: `total_fetched=1`, `updated=1`, `deleted=0`, `errors=0`
- Production bridge validation after deploy:
  - ECS service stabilized
  - live task definition: `chatproxy-prod-bridge:2`
  - public UI response: HTTP `200` from `https://aidcec-ai-agent.com`

Operational note:

- The earlier Mongo replacement side effect was contained before the bridge rollout resumed.
- This checklist is no longer only a plan; it also records the successful execution outcome for the candidate scope.

## Rollout target

- Branch: `release/aws-prod-candidate`
- Commit: `d8edea2`
- Candidate service versions:
  - `bridge`: `1.0.1`
  - `flowise-proxy`: `1.0.1`

## Use case for this checklist

Use this if you choose to promote commit `d8edea2` with explicit acceptance of the remaining dev Flowise sync-auth uncertainty.

Current baseline note:

- prod `flowise-proxy` is ECS-stable but already showing scheduled chatflow sync `401 Unauthorized` errors in CloudWatch
- treat this rollout as a controlled intervention on top of an already-non-clean backend baseline, not a deploy onto a clean steady state

## Preconditions

Before any production mutation:

1. Confirm the branch you intend to deploy is exactly `release/aws-prod-candidate` at commit `d8edea2`.
2. Confirm production is still healthy with the read-only audit path.
3. Confirm the production Flowise fallback secret still exists.
4. Confirm you are prepared to use the updated rollback workflow if needed.
5. Confirm you understand that `flowise-proxy` is already emitting scheduled sync `401` errors before rollout.

## Baseline capture

Run these before deployment and record the results.

### ECS baseline

```powershell
powershell -ExecutionPolicy Bypass -File .\infra\scripts\audit-ecs-status.ps1 -Environment prod -AsJson
```

Record:

- current prod task definitions
- current prod image tags
- service health summary
- current `flowise-proxy` log error pattern if `recent-errors:*` appears

### Secret presence baseline

```powershell
aws secretsmanager describe-secret `
  --secret-id /chatproxy/prod/flowise/api-key `
  --region us-east-1 `
  --output json
```

### Log baseline

```powershell
aws logs tail /ecs/chatproxy-prod-flowise-proxy --since 30m --region us-east-1
aws logs tail /ecs/chatproxy-prod-bridge --since 30m --region us-east-1
```

## Push and branch visibility

The GitHub Actions workflow must be able to see the candidate branch/ref.

If the branch is not already on the remote, push it first.

Suggested command:

```powershell
git push -u origin release/aws-prod-candidate
```

Do not dispatch production from the wrong branch.

## Rollout order

Deploy in this order:

1. `flowise-proxy`
2. `bridge`

Reason:

- `flowise-proxy` owns the admin runtime Flowise key status/test/update behavior
- `bridge` consumes those APIs

## Workflow to use

Use:

- `.github/workflows/deploy-prod.yml`

This workflow is manual and single-service per run.

## Step-by-step rollout

### Step 1 - Deploy `flowise-proxy`

In GitHub Actions:

1. Open `Deploy Prod`.
2. Choose branch/ref `release/aws-prod-candidate`.
3. Set `service=flowise-proxy`.
4. Start the workflow.

Watch for successful completion of:

1. secret validation
2. image tag generation using `version.json`
3. Docker build and ECR push
4. Terraform init
5. targeted Terraform apply
6. ECS wait for stability

Expected image family outcome:

- `flowise-proxy` should build as `v1.0.1-<gitsha7>` using the candidate SHA

### Step 2 - Validate `flowise-proxy`

Immediately after the deploy:

1. Confirm ECS service stability.
2. Confirm no startup regression in CloudWatch.
3. Sign in to the Bridge admin UI.
4. Open `Admin -> Settings`.
5. Confirm Flowise API key status loads.
6. Confirm key testing works.
7. If you have the correct key and need to, use runtime key update to correct the effective key.
8. Trigger or observe chatflow sync behavior and confirm the pre-existing unauthorized pattern stops.

Key production watch items:

- whether the pre-existing `Flowise API returned HTTP 401` pattern continues after validation
- whether key status, key test, and manual sync now succeed against the effective production key

### Step 3 - Deploy `bridge`

Only continue if `flowise-proxy` validation is acceptable.

In GitHub Actions:

1. Open `Deploy Prod` again.
2. Choose branch/ref `release/aws-prod-candidate`.
3. Set `service=bridge`.
4. Start the workflow.

Watch for:

1. image tag generation using `version.json`
2. Docker build and ECR push
3. targeted Terraform apply
4. ECS wait for stability

Expected image family outcome:

- `bridge` should build as `v1.0.1-<gitsha7>` using the candidate SHA

### Step 4 - Validate `bridge`

1. Confirm the production UI loads.
2. Confirm admin login still works.
3. Confirm the `Admin` page loads.
4. Confirm the `Settings` tab loads.
5. Confirm the new admin panels affected by this release behave correctly.

## Monitoring during rollout

### ECS

```powershell
aws ecs describe-services `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-flowise-proxy-service chatproxy-prod-bridge `
  --region us-east-1 `
  --output json
```

### Logs

```powershell
aws logs tail /ecs/chatproxy-prod-flowise-proxy --since 15m --region us-east-1
aws logs tail /ecs/chatproxy-prod-bridge --since 15m --region us-east-1
```

### Waiters

```powershell
aws ecs wait services-stable `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-flowise-proxy-service `
  --region us-east-1

aws ecs wait services-stable `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-bridge `
  --region us-east-1
```

## Rollback triggers

Rollback if any of these occur:

1. ECS service does not stabilize.
2. ALB target health degrades.
3. Admin Settings panel fails to load after `flowise-proxy` deploy.
4. Production starts showing fresh Flowise `401 Unauthorized` sync errors.
5. Bridge UI regresses after the frontend deploy.

## Rollback order

### If backend behavior regresses

Rollback `flowise-proxy` first.

### If UI-only behavior regresses after backend is good

Rollback `bridge`.

Use:

- `.github/workflows/rollback.yml`

This branch includes prod-capable rollback workflow support.

## Post-rollout record

After rollout, record:

1. actual deployed commit/ref
2. actual image tags produced
3. whether key status/test/update worked in prod
4. whether any Flowise `401` recurred
5. whether rollback was needed

## Decision rule

### Lowest-risk path

Do not deploy until the dev verification checklist passes and the current prod key/auth problem is explained.

### Acceptable-risk path

Deploy `flowise-proxy` first from `d8edea2`, validate aggressively, use the runtime key management path to correct the effective key if needed, then deploy `bridge` only if backend behavior is acceptable.