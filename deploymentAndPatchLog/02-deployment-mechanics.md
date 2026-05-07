# Deployment Mechanics

## Core deployment paths in this repo

### 1. Local development deploy

`local-deploy.py` is for local Docker Compose only.

- It writes local `.env` files.
- It creates the shared Docker network.
- It brings up services in local order.
- It is not an AWS deployment path.

Your note that local deploy was updated and tested on this Windows machine is useful validation for local composition and local config generation, but it does not by itself validate ECS, Secrets Manager, ECR, Terraform, or CloudWatch behavior.

### 2. Manual local operator deploy to AWS

`infra/scripts/deploy-service.ps1` is the direct operator path.

For a selected service it does this:

1. Resolve service metadata.
2. Build a Docker image from the service source directory.
3. Push both a versioned image tag and `latest` to ECR.
4. Update the service image variable in `infra/environments/<env>/terraform.tfvars`.
5. Run `terraform apply -target=<service module>`.
6. Wait for the ECS service to become stable.
7. Optionally auto-rollback to the previous task definition if stability fails.

Important implications:

- This is a real production-capable path because the script accepts `-Environment prod`.
- It mutates local `terraform.tfvars`, which is useful for operator control but easier to drift than CI if used casually.
- It depends on local Docker, AWS CLI auth, and Terraform state access.

### 3. GitHub Actions deploy to dev

`.github/workflows/deploy-dev.yml` supports:

- automatic deploy on push to `main` when service paths or `version.json` change
- manual `workflow_dispatch`

It performs:

1. change detection
2. Flowise secret validation when `flowise-proxy` is involved
3. Docker build and ECR push
4. targeted Terraform apply in `infra/environments/dev`
5. ECS wait for stability

### 4. GitHub Actions deploy to prod

`.github/workflows/deploy-prod.yml` is the current production promotion path.

Key characteristics:

- manual only via `workflow_dispatch`
- one service per run
- services supported:
  - `auth-service`
  - `accounting-service`
  - `flowise-proxy`
  - `bridge`
- environment fixed to `prod`
- uses `terraform.ci.tfvars` plus a runtime `-var` override for the selected image URI

Operational meaning:

- Prod does not auto-deploy on branch pushes.
- Promotion is intentionally explicit and service-scoped.
- If you use `release/aws`, the workflow dispatch must be run from the intended branch/ref, not accidentally from `main`.

### 5. Rollback

`.github/workflows/rollback.yml` supports manual rollback for `dev` and `prod`.

It can:

- accept a specific task definition ARN
- or infer the previous ECS task definition revision
- update the ECS service to that revision
- wait until the service is stable again

## Service order for the patch you described

The repo documentation and runtime dependency both point to the same order:

1. `flowise-proxy`
2. `bridge`

Reason:

- `flowise-proxy` owns the admin-facing runtime key status and update endpoints.
- `bridge` consumes those endpoints.
- If both change, backend first avoids validating a new UI against an old API contract.

## Current environment model relevant to prod

Based on `infra/environments/prod/main.tf` and `infra/environments/prod/terraform.ci.tfvars`:

- region: `us-east-1`
- account: `168437900315`
- cluster name pattern: `chatproxy-prod-cluster`
- ECS services:
  - `chatproxy-prod-auth-service`
  - `chatproxy-prod-accounting-service`
  - `chatproxy-prod-flowise-proxy-service`
  - `chatproxy-prod-bridge`
- supporting infra includes:
  - platform VPC and ALB
  - MongoDB EC2 module
  - RDS Postgres module
  - Secrets Manager module
  - WireGuard module

## Notable mechanics that affect patch safety

### Immutable versus mutable image references

- `auth-service`, `flowise-proxy`, and `bridge` are currently using immutable looking tags such as `v1.0.0-b7d1ef7`.
- `accounting-service` is still using `latest` in prod tfvars.

This matters because:

- immutable tags make promotion and rollback traceable
- `latest` weakens forensic clarity and rollback confidence

### Secret gate for `flowise-proxy`

Both deploy workflows validate `/chatproxy/<env>/flowise/api-key` before a `flowise-proxy` rollout.

This is a real release gate, not just documentation.

### The broad branch scope problem

The workflows are service-scoped, but the branch is not currently scope-safe.

That means:

- dispatching `Deploy Prod` for `flowise-proxy` or `bridge` from `release/aws` will build from the entire branch state at that ref
- unrelated infra or backend changes in the branch may still be part of what you are promoting indirectly
- the prod patch should be narrowed at the git scope level before rollout if only a subset is intended