# Quick Reference: Patch Deployment

## Quick Start - Local Patch

### Option 1: Full Automated Patch (Recommended)

```powershell
# Test + Build + Deploy + Smoke Test
.\patch_local.ps1 -ServiceName auth-service -Action Full

# Or for all services
.\patch_local.ps1 -ServiceName all -Action Full
```

### Option 2: Step-by-Step

```powershell
# Just run tests
.\patch_local.ps1 -ServiceName auth-service -Action Test

# Just build Docker images
.\patch_local.ps1 -ServiceName auth-service -Action Build

# Just deploy
.\patch_local.ps1 -ServiceName auth-service -Action Deploy
```

### Manual Testing

```powershell
cd auth-service
npm test
npm run lint
docker build -f Dockerfile -t auth-service:patch .
docker compose -f docker-compose.dev.yml down
docker compose -f docker-compose.dev.yml up -d
curl http://localhost:3000/health

cd ../accounting-service
# ... repeat for each service
```

---

## Quick Start - AWS Patch

### Phase 1: Prepare and Validate on `test/localdeploy`

```powershell
# 1. Make code changes on a short-lived branch
git add .
git commit -m "[TICKET_ID] - Description"
git push origin feat/your-change

# 2. Merge the tested change set into test/localdeploy
git checkout test/localdeploy
git pull origin test/localdeploy
git merge --ff-only feat/your-change
git push origin test/localdeploy

# 3. Run the service builds, tests, and smoke checks for the touched bundle
```

### Phase 2: Windows Production Deployment (`bhss`)

```powershell
# After test/localdeploy validation passes

# 1. Promote the tested commit set to bhss
git checkout bhss
git merge --ff-only test/localdeploy
git push origin bhss

# 2. Deploy on the Windows + Docker Desktop target
# 3. Run the BHSS smoke and admin patch checks
```

### Phase 3: AWS Production Deployment

See `AWS_PROD_PATCH_RUNBOOK.md` for the full production procedure.

```powershell
# After bhss deployment is validated

# 1. Promote the same commit set to the AWS production branch
git checkout release/aws-prod-candidate
git merge --ff-only test/localdeploy
git push origin release/aws-prod-candidate

# 2. Read-only preflight
.\infra\scripts\deploy-service.ps1 -Service <service> -Environment prod -Preflight
.\infra\scripts\audit-ecs-status.ps1 -Environment prod

# 3. Dry run the exact helper path
.\infra\scripts\deploy-service.ps1 -Service <service> -Environment prod -DryRun

# 4. Deploy one service at a time with rollback protection
.\infra\scripts\deploy-service.ps1 -Service <service> -Environment prod -AutoRollback

# 5. Re-audit and run the prod smoke subset after each service
.\infra\scripts\audit-ecs-status.ps1 -Environment prod
```

---

## Service Port Reference

### Local (Docker Compose)

```text
3000  - Auth Service
3001  - Accounting Service
3082  - Bridge UI
8000  - Flowise Proxy
3002  - Flowise (optional)
```

### AWS (ALB)

```text
http://<alb-endpoint>/api/auth        - Auth Service
http://<alb-endpoint>/api/accounting  - Accounting Service
http://<alb-endpoint>/api/chat        - Flowise Proxy
http://<alb-endpoint>/                - Bridge UI
```

---

## Health Check URLs

### Local

```bash
curl http://localhost:3000/health        # Auth
curl http://localhost:3001/health        # Accounting
curl http://localhost:8000/health        # Flowise Proxy
curl http://localhost:3082               # Bridge
```

### AWS

```bash
curl http://<alb-dns>/api/auth/health       # Auth
curl http://<alb-dns>/api/accounting/health # Accounting
curl http://<alb-dns>/api/chat/health       # Flowise Proxy
curl http://<alb-dns>/                      # Bridge
```

---

## Troubleshooting

### Local Service Not Starting

```powershell
# Check logs
docker compose -f auth-service/docker-compose.dev.yml logs

# Restart the service
docker compose -f auth-service/docker-compose.dev.yml restart

# Full rebuild
docker compose -f auth-service/docker-compose.dev.yml down -v
docker compose -f auth-service/docker-compose.dev.yml up -d
```

### AWS Deployment Stuck

```powershell
# Check ECS service status
aws ecs describe-services `
    --cluster chatproxy-prod-cluster `
    --services auth-service `
    --query 'services[0].deployments'

# Check logs
aws logs tail /chatproxy/prod/auth-service --follow

# Force new deployment
aws ecs update-service `
    --cluster chatproxy-prod-cluster `
    --service auth-service `
    --force-new-deployment
```

### Rollback Local

```powershell
# Revert to previous commit
git revert <bad-commit-hash>

# Rebuild the local stack from the reverted workspace
.\patch.ps1 -Mode full
.\diagnose.ps1 -Quick
```

### Rollback AWS

```powershell
# Fastest safe restore: redeploy the previous known-good image tag
.\infra\scripts\deploy-service.ps1 -Service <service> -Environment prod -Tag <previous-good-tag> -AutoRollback

# If you already captured the previous task definition ARN
aws ecs update-service `
    --cluster chatproxy-prod-cluster `
    --service chatproxy-prod-<service-suffix> `
    --task-definition <previous-task-definition-arn> `
    --region us-east-1

aws ecs wait services-stable `
    --cluster chatproxy-prod-cluster `
    --services chatproxy-prod-<service-suffix> `
    --region us-east-1
```

Use `git revert` after service recovery if you need to make the rollback durable on `release/aws-prod-candidate`.

---

## Monitoring Commands

### Local Services

```powershell
# Check all running containers
docker ps --format "table {{.Names}}\t{{.Status}}"

# View logs for a service
docker compose -f auth-service/docker-compose.dev.yml logs -f

# Check resource usage
docker stats
```

### AWS Services

```powershell
# Read-only environment audit
.\infra\scripts\audit-ecs-status.ps1 -Environment prod

# View CloudWatch logs
aws logs tail /chatproxy/prod/<service> --follow

# Check ECS service rollout
aws ecs describe-services `
    --cluster chatproxy-prod-cluster `
    --services chatproxy-prod-<service-suffix> `
    --region us-east-1 `
    --query 'services[0].{taskDefinition:taskDefinition,rollout:deployments[0].rolloutState,running:runningCount,desired:desiredCount}'

# Check ECS tasks
aws ecs list-tasks --cluster chatproxy-prod-cluster

# Get task details
aws ecs describe-tasks `
    --cluster chatproxy-prod-cluster `
    --tasks <task-arn>
```

---

## Common Patches

### Database Schema Migration

#### Local Database Migration

```powershell
# Backup current database
docker exec mongodb-accounting mongodump --out /backup

# Run migration scripts
npm run migrate

# Verify
npm test
```

#### AWS Database Migration

```powershell
# Backup Aurora RDS
aws rds create-db-snapshot `
    --db-instance-identifier accounting-db-prod `
    --db-snapshot-identifier accounting-backup-$(Get-Date -Format 'yyyyMMdd')

# Deploy with migration
git push origin release/aws-prod-candidate
# Monitor GitHub Actions
```

### Dependency Update (npm)

```powershell
cd auth-service
npm update
npm audit fix
npm test
git add package*.json
git commit -m "[DEPS] Update dependencies"
```

### Security Patch (CVE)

```powershell
# Check vulnerabilities
npm audit

# Fix automatically
npm audit fix

# If not fixed, manually update
npm install package-name@latest

# Test and commit
npm test
git commit -m "[SECURITY] Fix CVE-YYYY-XXXX"
```

---

## Environment-Specific Teardown

### Local Cleanup

```powershell
# Stop all containers
docker compose -f auth-service/docker-compose.dev.yml down
docker compose -f accounting-service/docker-compose.yml down
docker compose -f bridge/docker-compose.yml down
docker compose -f flowise-proxy-service-py/docker-compose.yml down

# Remove volumes (WARNING: DELETES DATA)
docker volume rm chatproxy-*

# Remove images
docker rmi auth-service accounting-service bridge flowise-proxy
```

### AWS Destroy (Development Only)

```powershell
# WARNING: This destroys all AWS resources

cd infra/environments/dev
terraform destroy -var-file=terraform.tfvars
```

---

## Backup Before Patching

### Local Backup

```powershell
$backupDir = "backups/backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -Path $backupDir -ItemType Directory

# Backup docker volumes
docker run --rm `
    -v mongodb-auth:/data `
    -v $backupDir/mongodb-auth:/backup `
    ubuntu tar czf /backup/mongodb-auth.tar.gz /data

# Backup docker-compose files
Copy-Item -Path docker-compose*.yml -Destination $backupDir/ -Recurse
```

### AWS Backup

```powershell
# Aurora snapshots are automatic
# But create manual snapshot before major patch
cd infra/environments/prod

aws rds create-db-snapshot `
    --db-instance-identifier accounting-db-prod `
    --db-snapshot-identifier pre-patch-$(Get-Date -Format 'yyyyMMdd')

aws rds create-db-snapshot `
    --db-instance-identifier flowise-db-prod `
    --db-snapshot-identifier pre-patch-$(Get-Date -Format 'yyyyMMdd')
```

---

## Key Decision Matrix

| Scenario | test/localdeploy | bhss (Windows prod) | AWS prod |
| ---------- | ------------------ | --------------------- | ---------- |
| Critical Security Patch | Immediate fix + validate | Promote and deploy as soon as validated | Promote and deploy in maintenance window or immediately if required |
| Bug Fix | Validate full bundle | Deploy after local validation passes | Deploy after bhss confirmation |
| Feature | Build and validate on feature branch, then merge | Deploy the same tested commit set | Deploy the same tested commit set after bhss sign-off |
| Dependency Update | Validate install, build, and smoke checks | Deploy and observe runtime behavior on Windows | Deploy and observe AWS runtime behavior |
| Database Migration | Backup and validate migration locally | Deploy with Windows-specific runbook checks | Deploy with Terraform and AWS rollback checks |

---

## Files to Monitor

| File | Purpose | When to Check |
| ------ | --------- | --------------- |
| `AWS_PROD_PATCH_RUNBOOK.md` | Current AWS production patch procedure | Before starting AWS prod patch |
| `AWS_PATCH_PIPELINE_RUNBOOK.md` | Current AWS dev patch procedure | Before starting AWS dev patch |
| `DEPLOYMENT_CHECKLIST.md` | Deployment requirements | Before deployment |
| `DEPLOYMENT_PROGRESS.md` | Current status | During deployment |
| `patch.ps1` | Local workstation patch automation | Running local patch |
| `infra/scripts/deploy-service.ps1` | ECS image deploy helper | Running AWS patch |
| `infra/scripts/audit-ecs-status.ps1` | Read-only ECS audit | Before and after AWS patch |
| GitHub Actions | CI/CD execution | After pushing to `test/localdeploy`, `bhss`, or `release/aws-prod-candidate` |
| CloudWatch Logs | Production logs | During prod monitoring |

---

## Emergency Contacts

### On-Call Rotation

[Insert team member names and schedules]

### Escalation Path

1. Current on-call engineer
2. Tech lead
3. Engineering manager
4. CTO

---

## Success Criteria

### Local Patch Success

- All unit tests pass
- All smoke tests pass
- No service downtime
- Git commits created

### `test/localdeploy` Validation Success

- Touched services build and test successfully
- Required smoke checks pass
- The intended patch bundle is merged cleanly into `test/localdeploy`

### `bhss` Deployment Success

- The same tested commit set is promoted to `bhss`
- Windows + Docker Desktop health checks pass
- Admin smoke tests pass on the live Windows deployment line
- Error logs are reviewed with no high-severity regressions

### AWS Production Patch Success

- Zero-downtime deployment
- All health checks pass
- 2-hour monitoring passes
- No error rate increase
- User reports: none
