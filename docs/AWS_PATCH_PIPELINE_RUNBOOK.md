# AWS Patch Pipeline Runbook

This runbook covers patching AWS through the existing dev ECS pipeline.

## Scope

Only these recent changes belong in the AWS patch rollout:

- `flowise-proxy-service-py/**`
- `bridge/**`
- `version.json` for image tag/version bumps

These changes do not belong in the AWS ECS rollout because they are workstation-only:

- `fleet.ps1`
- `scripts/create-fleet-user.ps1`
- other local setup or fleet bootstrap scripts

## Services To Deploy

Recommended rollout order:

1. `flowise-proxy`
2. `bridge`

Reason:

- `flowise-proxy` contains the runtime Flowise API key status, update, and test endpoints.
- `bridge` only exposes the admin UI that consumes those endpoints.

## Trigger Paths

There are two supported ways to patch dev AWS.

### Option 1: GitHub Actions automatic path

Merge the AWS-relevant changes to `main`.

Workflow:

- `.github/workflows/deploy-dev.yml`

Trigger conditions:

- push to `main` that changes `flowise-proxy-service-py/**`, `bridge/**`, or `version.json`
- manual `workflow_dispatch`

### Option 2: Manual per-service path

Use the local deploy helper:

```powershell
.\infra\scripts\deploy-service.ps1 -Service flowise-proxy -Environment dev -AutoRollback
.\infra\scripts\deploy-service.ps1 -Service bridge -Environment dev -AutoRollback
```

Use this path when you want explicit service-by-service rollout and local operator control.

## Pre-Deploy Checklist

1. Confirm the patch set contains only AWS-relevant files.
2. Bump service versions in `version.json` for `flowise-proxy` and `bridge`.
3. Confirm the dev Flowise fallback secret exists in AWS Secrets Manager:

```bash
aws secretsmanager describe-secret \
  --secret-id /chatproxy/dev/flowise/api-key \
  --region us-east-1
```

4. Confirm the secret contains a non-empty `FLOWISE_API_KEY` field:

```bash
aws secretsmanager get-secret-value \
  --secret-id /chatproxy/dev/flowise/api-key \
  --region us-east-1 \
  --query SecretString \
  --output text
```

Expected structure:

```json
{
  "FLOWISE_API_KEY": "<non-empty-value>"
}
```

Note:

- The deploy pipeline now validates this automatically when `flowise-proxy` is part of the rollout.
- Runtime key updates in the app do not remove the need for a valid startup fallback secret in ECS.

## GitHub Actions Rollout Procedure

1. Merge AWS-relevant changes to `main`.
2. Open GitHub Actions and monitor `Deploy Dev`.
3. Confirm these stages pass:

- change detection
- secret validation
- Docker build and ECR push
- Terraform apply
- ECS wait for service stability

4. If both services changed together, verify `flowise-proxy` deploy completes before validating `bridge` behavior.

## Manual Workflow Dispatch Procedure

If you want controlled rollout without waiting for path-based change detection:

1. Open `Deploy Dev` in GitHub Actions.
2. Run manually with `service=flowise-proxy`.
3. Validate runtime key endpoints and ECS stability.
4. Run manually with `service=bridge`.
5. Validate the admin UI Settings tab.

## Post-Deploy Validation

Validate both infrastructure and behavior.

### Infrastructure validation

1. Confirm ECS services are stable.
2. Confirm target groups are healthy.
3. Confirm CloudWatch logs do not show startup or auth regressions.

### Functional validation

1. Sign in as an admin through the Bridge UI.
2. Open Admin -> Settings.
3. Confirm Flowise API key status loads.
4. Confirm key testing works.
5. Confirm updating the key succeeds.
6. Confirm subsequent proxy operations use the new key without a new ECS deployment.

## Rollback

If rollout fails, use the manual rollback workflow:

- `.github/workflows/rollback.yml`

Rollback order:

1. `bridge` if the UI is broken but backend is healthy.
2. `flowise-proxy` if runtime endpoint behavior regressed.

If both were deployed and proxy behavior is the root issue, rollback `bridge` only if necessary for UI recovery, but prioritise restoring `flowise-proxy` first.

## Operator Notes

- Workstation fleet bootstrap changes are a separate rollout stream and should be patched via the fleet path, not ECS.
- Keep the Flowise API key in Secrets Manager current even after runtime admin updates are introduced.
- Treat the runtime-stored key as the live operational override and Secrets Manager as the safe startup baseline.