# AWS Production Patch Runbook

This runbook is the current manual procedure for patching AWS production ECS services from this repository.

Branch workflow note:

- Build and validate on `test/localdeploy` first.
- Promote the exact tested commit set to `release/aws-prod-candidate`.
- Patch only the services in scope. Do not mix workstation-only scripts into an AWS ECS rollout.

## Use This Runbook When

- You need a controlled production rollout for `auth-service`, `accounting-service`, `flowise-proxy`, or `bridge`.
- You want a service-by-service deployment with dry-run review and rollback protection.
- The change only updates one or more ECS service images and does not require a broad infrastructure change.

## Safety Rules

1. Do not deploy directly from an unvalidated feature branch.
2. Do not deploy every service just because multiple services exist. Deploy only the changed bundle.
3. Deploy backend owners before their callers. If `bridge` is in scope, deploy it last.
4. Use immutable image tags. Treat `latest` as a convenience tag, not as the deployment identifier.
5. Stop on the first failed smoke check, suspicious log pattern, or unexpected ECS drift.
6. Prefer targeted ECS module updates through `infra/scripts/deploy-service.ps1` over a broad `terraform apply` when only one service image changes.

## Service Map

| Service | Deploy helper value | Terraform module | ECS service name |
| --- | --- | --- | --- |
| Auth Service | `auth-service` | `module.auth_ecs` | `chatproxy-prod-auth-service` |
| Accounting Service | `accounting-service` | `module.accounting_ecs` | `chatproxy-prod-accounting-service` |
| Flowise Proxy | `flowise-proxy` | `module.flowise_proxy_ecs` | `chatproxy-prod-flowise-proxy-service` |
| Bridge | `bridge` | `module.bridge_ecs` | `chatproxy-prod-bridge` |

## Preflight

1. Confirm the tested commit set is already on `release/aws-prod-candidate`.

```powershell
git checkout release/aws-prod-candidate
git merge --ff-only test/localdeploy
git push origin release/aws-prod-candidate
```

1. Audit the current production state before changing anything.

```powershell
.\infra\scripts\audit-ecs-status.ps1 -Environment prod
aws sts get-caller-identity
```

1. Run the service-specific deploy preflight before any dry run or deployment.

```powershell
.\infra\scripts\deploy-service.ps1 -Service bridge -Environment prod -Preflight
```

The preflight is read-only. It shows the live ECS service name, current task definition, current ECS image, current `terraform.tfvars` image, and the planned image tag that the helper would deploy.

1. Record the current live task definition for each service in scope.

```powershell
aws ecs describe-services `
    --cluster chatproxy-prod-cluster `
    --services chatproxy-prod-bridge `
    --region us-east-1 `
    --query 'services[0].taskDefinition' `
    --output text
```

Replace `chatproxy-prod-bridge` with the ECS service you are rolling out.

1. Run a dry run for each service you plan to deploy.

```powershell
.\infra\scripts\deploy-service.ps1 -Service bridge -Environment prod -DryRun
```

1. If `flowise-proxy` is in scope, verify the production Flowise API key fallback secret before rollout.

```powershell
aws secretsmanager describe-secret `
    --secret-id /chatproxy/prod/flowise/api-key `
    --region us-east-1

aws secretsmanager get-secret-value `
    --secret-id /chatproxy/prod/flowise/api-key `
    --region us-east-1 `
    --query SecretString `
    --output text
```

1. Resolve the production endpoint for smoke tests.

```powershell
Push-Location .\infra\environments\prod
terraform output -raw alb_dns_name
Pop-Location
```

## Versioning

If you want to bump `version.json` before deployment, use the helper without automatic git tagging and then review the result manually.

```powershell
.\infra\scripts\bump-version.ps1 -Service bridge -Type patch -NoTag
```

Review and commit `version.json` yourself after the bump. This avoids mixing the version change with older branch or tag assumptions.

## Deployment Procedure

1. Deploy one service at a time.

```powershell
.\infra\scripts\deploy-service.ps1 -Service bridge -Environment prod -AutoRollback
```

1. Immediately re-audit production after the deployment finishes.

```powershell
.\infra\scripts\audit-ecs-status.ps1 -Environment prod
```

1. Tail the service logs while you run the smoke check.

```powershell
aws logs tail /chatproxy/prod/bridge --follow
```

1. Run the smallest production smoke check that proves the changed behavior.

## Focused Smoke Checks

Use the smallest meaningful check set after each service deploy.

| Service | Minimum production smoke |
| --- | --- |
| `auth-service` | Admin login, token refresh, and the changed auth or admin path |
| `accounting-service` | Credit balance or allocation flow that crosses the changed endpoint |
| `flowise-proxy` | `/api/chat/health` plus the changed proxy or settings endpoint |
| `bridge` | Load the UI, sign in as admin if relevant, and exercise the changed screen once |

If the patch is admin-facing, rerun the smallest relevant subset from `ADMIN_PATCH_TEST_CASES.md` instead of inventing a new smoke test.

## Known Fallback If The Helper Script Misbehaves

If `deploy-service.ps1` updates `terraform.tfvars` but fails around the targeted Terraform apply, use the same narrow target manually rather than widening to a full environment apply.

```powershell
Push-Location .\infra\environments\prod
& terraform apply '-var-file=terraform.tfvars' '-target=module.bridge_ecs' '-auto-approve'
Pop-Location

aws ecs wait services-stable `
    --cluster chatproxy-prod-cluster `
    --services chatproxy-prod-bridge `
    --region us-east-1
```

Match the module and ECS service name to the service you are deploying.

## Rollback

1. If ECS does not stabilise and `-AutoRollback` succeeds, stop the rollout and inspect before deploying anything else.
1. If ECS stabilises but the smoke test fails, restore the previous known-good image tag first.

```powershell
.\infra\scripts\deploy-service.ps1 -Service bridge -Environment prod -Tag <previous-good-tag> -AutoRollback
```

1. If you already captured the previous task definition ARN, you can restore it directly.

```powershell
aws ecs update-service `
    --cluster chatproxy-prod-cluster `
    --service chatproxy-prod-bridge `
    --task-definition <previous-task-definition-arn> `
    --region us-east-1

aws ecs wait services-stable `
    --cluster chatproxy-prod-cluster `
    --services chatproxy-prod-bridge `
    --region us-east-1
```

1. After the service is healthy again, make the rollback durable by reverting or correcting `release/aws-prod-candidate` and then redeploying cleanly.

## Do Not Use This Runbook For

- Workstation or fleet patching through `patch.ps1` or `fleet.ps1`
- Full infrastructure changes that need a reviewed production Terraform plan across multiple modules
- A new feature bundle that has not already been validated on `test/localdeploy`
