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

### Phase 1: Dev Deployment
```powershell
# 1. Make code changes locally
git add .
git commit -m "[TICKET_ID] - Description"
git push origin main

# 2. Merge to release/aws (triggers GitHub Actions)
git checkout release/aws
git pull origin release/aws
git merge main
git push origin release/aws

# 3. Monitor deployment (in separate terminal)
.\patch_aws.ps1 -Environment dev -Action Monitor -Duration 120
```

### Phase 2: Staging Deployment
```powershell
# After 24+ hours in dev with no issues

# 1. Create release branch
git checkout -b release/staging-v1.x.x release/aws
git push origin release/staging-v1.x.x

# 2. Trigger staging deployment via GitHub Actions UI
# 3. Monitor
.\patch_aws.ps1 -Environment staging -Action Monitor -Duration 120
```

### Phase 3: Production Deployment
```powershell
# After 24+ hours in staging with no issues

# 1. Ensure on main branch with latest changes
git checkout main
git pull origin main

# 2. Upgrade via Terraform (production)
cd infra/environments/prod

# Plan first
terraform plan -var-file=terraform.tfvars -out=tfplan

# Review the plan carefully
cat tfplan

# Apply (REQUIRES APPROVAL)
terraform apply tfplan

# 3. Monitor production
.\patch_aws.ps1 -Environment prod -Action Monitor -Duration 120

# 4. Post-deployment check (after 2 hours)
.\patch_aws.ps1 -Environment prod -Action Status
```

---

## Service Port Reference

### Local (Docker Compose)
```
3000  - Auth Service
3001  - Accounting Service
3082  - Bridge UI
8000  - Flowise Proxy
3002  - Flowise (optional)
```

### AWS (ALB)
```
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

# Rebuild
.\automated_setup.bat
```

### Rollback AWS
```powershell
# Quick revert (fastest)
git revert -m 1 <bad-merge-commit>
git push origin release/aws
# GitHub Actions will automatically redeploy

# Or monitor rollback
.\patch_aws.ps1 -Environment prod -Action Rollback
```

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
# Get deployment status
.\patch_aws.ps1 -Environment prod -Action Status

# View CloudWatch logs
aws logs tail /chatproxy/prod/auth-service --follow

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
**Local:**
```powershell
# Backup current database
docker exec mongodb-accounting mongodump --out /backup

# Run migration scripts
npm run migrate

# Verify
npm test
```

**AWS:**
```powershell
# Backup Aurora RDS
aws rds create-db-snapshot `
    --db-instance-identifier accounting-db-prod `
    --db-snapshot-identifier accounting-backup-$(Get-Date -Format 'yyyyMMdd')

# Deploy with migration
git push origin release/aws
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

| Scenario | Local | AWS Dev | AWS Staging | AWS Prod |
|----------|-------|---------|-------------|----------|
| Critical Security Patch | Immediate + test | Immediate | 4-6 hours | During maintenance |
| Bug Fix | Test + deploy | 24h wait | 24h wait | 48h wait |
| Feature | New branch + test | Staging first | Prod after 48h | Scheduled release |
| Dependency Update | Test immediately | Dev first | Staging 24h | Staging + 48h prod |
| Database Migration | Backup + test | Dev + backup | Staging + backup | Prod + backup |

---

## Files to Monitor

| File | Purpose | When to Check |
|------|---------|---------------|
| `PATCHING_STRATEGY.md` | Full strategy document | Before starting patch |
| `DEPLOYMENT_CHECKLIST.md` | Deployment requirements | Before deployment |
| `DEPLOYMENT_PROGRESS.md` | Current status | During deployment |
| `patch_local.ps1` | Local automation | Running local patch |
| `patch_aws.ps1` | AWS automation | Running AWS patch |
| GitHub Actions | CI/CD execution | After pushing to release/aws |
| CloudWatch Logs | Production logs | During prod monitoring |

---

## Emergency Contacts

**On-Call Rotation:** [Insert team member names and schedules]

**Escalation Path:**
1. Current on-call engineer
2. Tech lead
3. Engineering manager
4. CTO

---

## Success Criteria

✅ **Local Patch Success:**
- All unit tests pass
- All smoke tests pass
- No service downtime
- Git commits created

✅ **Dev Patch Success:**
- GitHub Actions completes
- All health checks pass
- Integration tests pass
- 24-hour soak test passes

✅ **Staging Patch Success:**
- All health checks pass
- Integration tests pass
- 24-hour soak test passes
- Performance metrics stable
- Error logs reviewed

✅ **Production Patch Success:**
- Zero-downtime deployment
- All health checks pass
- 2-hour monitoring passes
- No error rate increase
- User reports: none
