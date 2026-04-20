# Long-Term TODO

## [DONE ✓ 2026-04-20] Apply AWS Flowise EFS Persistent Storage

**Priority**: High — without this, all Flowise chatflows and credentials are lost on every container restart.

### Background
Flowise on AWS ECS Fargate (`flowise.aidcec-ai-agent.com`) had no persistent storage. All data in `/root/.flowise` (chatflows, credentials, API keys) was ephemeral — wiped on any container restart, health check failure, or `terraform apply`. This caused a data loss incident on ~April 20, 2026.

### What Was Done
The Terraform code has been updated but **not yet applied to AWS**:
- `infra/modules/flowise-aws/main.tf` — Added EFS filesystem, access point, mount targets (2 AZs), EFS security group, IAM task role with EFS permissions, updated ECS task definition to mount EFS at `/root/.flowise`, added `lifecycle { ignore_changes = [desired_count] }` to ECS service
- `infra/environments/dev/terraform.tfvars` — Pinned Flowise image to `flowiseai/flowise:3.0.0` (was unpinned `latest`)

### Applied — AWS Resource IDs
- EFS filesystem: `fs-07b879e352f9e348d`
- EFS access point: `fsap-0e76a214bb76b0b5e`
- EFS mount target us-east-1a: `fsmt-085d625b43dda3276`
- EFS mount target us-east-1b: `fsmt-01c72fde419fd18a6`
- EFS security group: `sg-06a9dcaf15ad32977`
- IAM task role: `chatproxy-dev-flowise-task`

### Action Required
Run the following to apply the changes to AWS:

```powershell
cd infra/environments/dev
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars   # review first
terraform apply -var-file=terraform.tfvars
```

**Expected plan output**: ~7 new resources (EFS filesystem, access point, 2x mount targets, EFS SG, IAM task role, IAM policy) + updated task definition revision + ECS service update.

**Downtime**: Brief rolling restart of the Flowise ECS task. Safe to apply — current container has no data to lose.

### Verification After Apply
1. Visit `https://flowise.aidcec-ai-agent.com` — service should be healthy
2. Create a test chatflow
3. Force a task restart: `aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment --region us-east-1`
4. Confirm the test chatflow is still present after restart
5. Check CloudWatch logs (`/ecs/chatproxy-dev-flowise`) — should show Flowise finding existing data, not a fresh install

---

## [PENDING] Investigate Root Cause of April 2026 Flowise Data Loss

Even after EFS is applied, confirm what triggered the original restart so it doesn't recur:

1. **ECS service events** — AWS Console → ECS → dev cluster → flowise service → Events tab (reason for last task replacement)
2. **CloudWatch Logs** — `/ecs/chatproxy-dev-flowise` — look for OOM (exit 137), health check failures, or SIGTERM
3. **GitHub Actions** — Check `deploy-dev.yml` run history around April 20, 2026 — a push to `main` touching `version.json` runs `terraform apply -auto-approve` which can restart all services
4. **Task definition revision** — `aws ecs describe-task-definition --task-definition chatproxy-dev-flowise-task` — if revision number jumped, terraform was applied

---

## [FUTURE] Flowise Backup Strategy

Even with EFS, consider periodic backups of `/root/.flowise`:
- AWS Backup plan targeting the EFS filesystem (daily snapshots, 30-day retention)
- Or an ECS scheduled task that tarballs `/root/.flowise` to S3 nightly
