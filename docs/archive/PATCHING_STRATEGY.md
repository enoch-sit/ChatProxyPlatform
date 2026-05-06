# Systematic Patching Strategy - ChatProxy Platform

> Historical archive: this document preserves an older `main -> release/aws -> staging -> prod` workflow and does not reflect the current branch policy.
> For current operations, use [../BRANCHING_POLICY.md](../BRANCHING_POLICY.md), [../PATCH_QUICK_REFERENCE.md](../PATCH_QUICK_REFERENCE.md), and [../AWS_PATCH_PIPELINE_RUNBOOK.md](../AWS_PATCH_PIPELINE_RUNBOOK.md).

## Overview
This document defines a systematic approach to patch both **Local Windows Deployment** and **AWS Deployment** (dev/staging/prod) safely and effectively.

**Key Principles:**
- ✅ **Zero downtime** for production deployments
- ✅ **Automated testing** at each stage
- ✅ **Rollback capabilities** for critical failures
- ✅ **Audit trail** of all changes (Git commits + deployment logs)
- ✅ **Environment parity** — patches tested in lower environments first

---

## Part 1: Pre-Patch Planning

### 1.1 Patch Classification

**CRITICAL (Emergency)** — Security exploits, data corruption, complete service outage
- Bypass comprehensive testing if documented critical need
- Requires post-incident review

**HIGH** — Breaking bugs, significant performance degradation, major feature broken
- Test in dev → staging → production
- Announce maintenance window in advance

**MEDIUM** — Non-breaking bug fixes, minor improvements, dependency updates
- Test in dev → run in staging overnight → production next day
- Can deploy during low-traffic periods

**LOW** — Documentation, minor code cleanup, cosmetic changes
- Local testing sufficient
- Deploy during regular update windows

### 1.2 Change Log Template

**Before patching, create a change log:**

```markdown
# Patch: [TICKET_ID] - [Brief Title]
**Date**: YYYY-MM-DD
**Priority**: CRITICAL | HIGH | MEDIUM | LOW
**Affected Services**: auth-service | accounting-service | flowise-proxy | bridge | (all)
**Environments**: local | dev | staging | prod

## Changes
- [ ] Service 1: Description
- [ ] Service 2: Description

## Testing Checklist
- [ ] Unit tests pass (npm test)
- [ ] Docker build succeeds
- [ ] Local integration tests pass
- [ ] Dev environment tests pass
- [ ] Staging environment tests pass

## Rollback Plan
**Rollback Command**: git revert <commit-hash>
**Database Changes**: [Describe if any]
**Cache Flush Required**: Yes/No

## Timeline
- **Local Test**: [HH:MM]
- **Dev Deploy**: [HH:MM]
- **Staging Deploy**: [HH:MM]
- **Prod Deploy**: [HH:MM] (in maintenance window)
```

---

## Part 2: Local Windows Patching

### 2.1 Pre-Deployment Validation

**Step 1: Source Code Preparation**

```powershell
# 1. Fetch latest changes from repository
git fetch origin
git pull origin main

# 2. Create feature branch for patch
git checkout -b patch/[TICKET_ID]-[description]

# 3. Make code changes
# Edit files as needed

# 4. Stage changes
git add .
git commit -m "[TICKET_ID] - Detailed commit message"

# 5. Verify commit
git log --oneline -5
```

**Step 2: Unit Testing (Per Service)**

```powershell
# For each affected service:
# auth-service
cd auth-service
npm test
npm run lint
cd ..

# accounting-service
cd accounting-service
npm test
npm run lint
cd ..

# bridge (React frontend)
cd bridge
npm test
npm run lint
npm run build
cd ..

# flowise-proxy (Python)
cd flowise-proxy-service-py
python -m pytest tests/ -v
cd ..
```

**Step 3: Docker Build Verification**

```powershell
# Auth Service
cd auth-service
docker build -f Dockerfile -t auth-service:patch .
docker build -f Dockerfile.prod -t auth-service:patch-prod .
cd ..

# Accounting Service
cd accounting-service
docker build -f Dockerfile -t accounting-service:patch .
cd ..

# Bridge (React)
cd bridge
docker build -f Dockerfile -t bridge:patch .
cd ..

# Flowise Proxy
cd flowise-proxy-service-py
docker build -f Dockerfile -t flowise-proxy:patch .
cd ..

# Verify images built successfully
docker images | grep patch
```

### 2.2 Local Integration Testing

```powershell
# STOP all running containers first
docker compose -f auth-service/docker-compose.dev.yml down
docker compose -f accounting-service/docker-compose.yml down
docker compose -f bridge/docker-compose.yml down
docker compose -f flowise-proxy-service-py/docker-compose.yml down

# Clean up volumes if database schema changed
# docker volume rm <volume_name>

# START services with patched images
cd auth-service
docker compose -f docker-compose.dev.yml up -d

cd ../accounting-service
docker compose -f docker-compose.yml up -d

cd ../bridge
docker compose -f docker-compose.yml up -d

cd ../flowise-proxy-service-py
docker compose -f docker-compose.yml up -d

cd ..

# Wait for services to be healthy (30-60 seconds)
Start-Sleep -Seconds 60

# Verify service health
docker ps --format "table {{.Names}}\t{{.Status}}"

# Run integration tests
Write-Host "Running integration tests..."
Invoke-WebRequest -Uri "http://localhost:3000/health" -ErrorAction Stop
Invoke-WebRequest -Uri "http://localhost:3001/health" -ErrorAction Stop
Invoke-WebRequest -Uri "http://localhost:3082" -ErrorAction Stop
Invoke-WebRequest -Uri "http://localhost:8000/health" -ErrorAction Stop

Write-Host "✅ All services healthy"
```

### 2.3 Smoke Tests

**Create `test_patch.ps1`:**

```powershell
# Smoke tests for patch verification

function Test-AuthService {
    Write-Host "Testing Auth Service..."
    
    # Test login endpoint
    $response = Invoke-WebRequest -Uri "http://localhost:3000/api/auth/login" `
        -Method POST `
        -ContentType "application/json" `
        -Body '{"email":"test@example.com","password":"test"}' `
        -ErrorAction SilentlyContinue
    
    if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 401) {
        Write-Host "✅ Auth Service responsive"
        return $true
    }
    Write-Host "❌ Auth Service check failed"
    return $false
}

function Test-AccountingService {
    Write-Host "Testing Accounting Service..."
    
    $response = Invoke-WebRequest -Uri "http://localhost:3001/health" `
        -ErrorAction SilentlyContinue
    
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Accounting Service healthy"
        return $true
    }
    Write-Host "❌ Accounting Service check failed"
    return $false
}

function Test-Bridge {
    Write-Host "Testing Bridge UI..."
    
    $response = Invoke-WebRequest -Uri "http://localhost:3082" `
        -ErrorAction SilentlyContinue
    
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Bridge UI responsive"
        return $true
    }
    Write-Host "❌ Bridge UI check failed"
    return $false
}

function Test-FlowiseProxy {
    Write-Host "Testing Flowise Proxy..."
    
    $response = Invoke-WebRequest -Uri "http://localhost:8000/health" `
        -ErrorAction SilentlyContinue
    
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Flowise Proxy responsive"
        return $true
    }
    Write-Host "❌ Flowise Proxy check failed"
    return $false
}

# Run all tests
$results = @(
    Test-AuthService,
    Test-AccountingService,
    Test-Bridge,
    Test-FlowiseProxy
)

if ($results -contains $false) {
    Write-Host "❌ PATCH FAILED - Some services are not responding"
    exit 1
} else {
    Write-Host "✅ PATCH SUCCESSFUL - All services healthy"
    exit 0
}
```

**Run the smoke tests:**

```powershell
.\test_patch.ps1
```

### 2.4 Commit & Tag

```powershell
# After successful local testing

# 1. Merge to main
git checkout main
git pull origin main
git merge patch/[TICKET_ID]-[description]

# 2. Tag for reference
git tag -a v1.x.x-patch-[TICKET_ID] -m "[TICKET_ID] - Patch description"

# 3. Push changes
git push origin main
git push origin --tags

# 4. Mark change log as deployed locally
# Update PATCH_CHANGELOG.md with local deployment timestamp
```

---

## Part 3: AWS Patching Strategy

### 3.1 Understanding AWS Deployment Flow

```
Code Change
    ↓
Git Push to release/aws branch
    ↓
GitHub Actions CI/CD Triggered
    ↓
Build Docker Images → Push to ECR
    ↓
Update Terraform Variables (optional)
    ↓
Terraform Plan (validate)
    ↓
Terraform Apply (deploy)
    ↓
ECS Rolling Update (zero-downtime restart)
    ↓
Health Checks Pass
    ↓
Production Live
```

### 3.2 Patching Workflow: Dev → Staging → Prod

#### **Phase 1: DEV Deployment**

**Step 1: Push to release/aws branch (dev target)**

```powershell
# Ensure all local testing passed (see Part 2)

# Switch to release/aws branch
git checkout release/aws
git pull origin release/aws

# Merge main into release/aws
git merge main -m "Merge patch [TICKET_ID] from main"

# Push to trigger GitHub Actions
git push origin release/aws

Write-Host "✅ Pushed to release/aws - GitHub Actions will deploy to DEV"
Write-Host "⏳ Monitor: https://github.com/[org]/[repo]/actions"
```

**Step 2: Monitor GitHub Actions**

```powershell
# Open GitHub Actions dashboard and wait for:
# ✅ Build job (Docker images created)
# ✅ Push to ECR job (images uploaded)
# ✅ Terraform plan job (validates infrastructure)
# ✅ Terraform apply job (provisions infrastructure)
# ✅ Deploy ECS job (updates ECS services)

# Estimated time: 10-15 minutes
```

**Step 3: Validate DEV Deployment**

```powershell
# Get DEV environment details from Terraform outputs
cd infra/environments/dev

# Retrieve ALB endpoint
terraform output -raw alb_dns_name

# Test DEV environment
$devEndpoint = terraform output -raw alb_dns_name
Write-Host "Testing DEV: $devEndpoint"

# Test each service
Invoke-WebRequest -Uri "http://$devEndpoint/api/auth/health" 
Invoke-WebRequest -Uri "http://$devEndpoint/api/accounting/health" 
Invoke-WebRequest -Uri "http://$devEndpoint/api/chat/health" 
Invoke-WebRequest -Uri "http://$devEndpoint/" 

Write-Host "✅ DEV deployment validated"
```

**Step 4: DEV Integration Tests**

```powershell
# Run comprehensive API tests against DEV
$devEndpoint = terraform output -raw alb_dns_name

# Test authentication flow
$loginResponse = Invoke-WebRequest -Uri "http://$devEndpoint/api/auth/login" `
    -Method POST `
    -ContentType "application/json" `
    -Body '{"email":"admin@example.com","password":"admin123"}'

$token = ($loginResponse.Content | ConvertFrom-Json).accessToken

# Test accounting API
$accountsResponse = Invoke-WebRequest -Uri "http://$devEndpoint/api/accounting/credits" `
    -Method GET `
    -Headers @{ "Authorization" = "Bearer $token" }

# Test chat API
$chatResponse = Invoke-WebRequest -Uri "http://$devEndpoint/api/chat/messages" `
    -Method GET `
    -Headers @{ "Authorization" = "Bearer $token" }

Write-Host "✅ DEV integration tests passed"
```

---

#### **Phase 2: STAGING Deployment**

**Step 1: Create Release Branch**

```powershell
# Only after DEV passes validation for 24+ hours (optional, depends on severity)

# Create release candidate branch
git checkout -b release/staging-[VERSION] origin/release/aws
git push origin release/staging-[VERSION]
```

**Step 2: Deploy to Staging**

```powershell
# Create a separate workflow trigger for staging
# Option A: Merge to staging-release branch (if configured)
# Option B: Manually trigger GitHub Actions workflow

# Manual workflow trigger:
# 1. Go to GitHub Actions → "Deploy to Staging"
# 2. Click "Run workflow"
# 3. Select branch: release/staging-[VERSION]
# 4. Click "Run workflow"

Write-Host "⏳ Staging deployment initiated"
```

**Step 3: Staging Validation**

```powershell
# Wait for GitHub Actions to complete staging deployment

# Retrieve staging ALB endpoint
cd infra/environments/staging
$stagingEndpoint = terraform output -raw alb_dns_name

# Run same tests as DEV
Write-Host "Testing Staging: $stagingEndpoint"
Invoke-WebRequest -Uri "http://$stagingEndpoint/api/auth/health"
Invoke-WebRequest -Uri "http://$stagingEndpoint/api/accounting/health"
Invoke-WebRequest -Uri "http://$stagingEndpoint/api/chat/health"

Write-Host "✅ Staging deployment validated"
```

**Step 4: Staging Soak Test (Minimum 24 hours)**

- Monitor CloudWatch logs for errors
- Monitor application performance (latency, error rate)
- Verify database replication health
- Check backup completion

```powershell
# CloudWatch logs check
aws logs tail /chatproxy/staging/auth-service --follow
aws logs tail /chatproxy/staging/accounting-service --follow
aws logs tail /chatproxy/staging/flowise-proxy --follow
```

---

#### **Phase 3: PRODUCTION Deployment**

**⚠️ PRODUCTION DEPLOYMENT CHECKLIST:**

- [ ] DEV passing for 24+ hours
- [ ] Staging passing for 24+ hours with no anomalies
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Database migrations tested in staging
- [ ] Rollback plan documented
- [ ] On-call engineer available
- [ ] Maintenance window scheduled (if needed)
- [ ] Stakeholders notified

**Step 1: Production Deployment with Ramped Rollout**

```powershell
# Production uses BLUE-GREEN deployment for zero downtime

# Option 1: GitHub Action Approval Gate
# 1. Go to GitHub Actions → "Deploy to Production"
# 2. Review changes
# 3. Click "Approve and Deploy"

# Option 2: Manual Terraform Apply
cd infra/environments/prod

# IMPORTANT: Verify terraform.tfvars hasn't changed unexpectedly
cat terraform.tfvars

# Plan first (ALWAYS)
terraform plan -var-file=terraform.tfvars -out=tfplan

# Review the plan carefully
# If CRITICAL changes detected, STOP and investigate

# Apply only after approval
terraform apply tfplan

Write-Host "🚀 Production deployment initiated"
```

**Step 2: Monitor Production Rollout**

```powershell
# ECS Rolling Update (Max 2 per service during production)
# - Old tasks gradually stop
# - New tasks gradually start (uses new Docker image)
# - ALB drains connections from old tasks
# - Zero downtime if health checks pass

# Monitor ECS service updates
$region = "us-east-1"
aws ecs describe-services `
    --cluster chatproxy-prod-cluster `
    --services auth-service accounting-service flowise-proxy bridge `
    --region $region `
    --query 'services[*].[serviceName,deployments[0].status,deployments[1].status]' `
    --output table

# Monitor ALB target health
aws elbv2 describe-target-health `
    --target-group-arn arn:aws:elasticloadbalancing:$region:ACCOUNT:targetgroup/chatproxy-prod-auth/... `
    --region $region

# Watch CloudWatch logs for errors
aws logs tail /chatproxy/prod/auth-service --follow
aws logs tail /chatproxy/prod/accounting-service --follow
aws logs tail /chatproxy/prod/flowise-proxy --follow
```

**Step 3: Verify Production**

```powershell
# Get production endpoint
cd infra/environments/prod
$prodEndpoint = terraform output -raw alb_dns_name

# Comprehensive production verification
Write-Host "🔍 Verifying Production Deployment..."

# 1. Health checks
$healthTests = @(
    "http://$prodEndpoint/api/auth/health",
    "http://$prodEndpoint/api/accounting/health",
    "http://$prodEndpoint/api/chat/health",
    "http://$prodEndpoint/"
)

foreach ($url in $healthTests) {
    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 5
        Write-Host "✅ $url - OK"
    } catch {
        Write-Host "❌ $url - FAILED"
        exit 1
    }
}

# 2. Authentication flow
$loginResponse = Invoke-WebRequest -Uri "http://$prodEndpoint/api/auth/login" `
    -Method POST `
    -ContentType "application/json" `
    -Body '{"email":"admin@example.com","password":"admin123"}'

if ($loginResponse.StatusCode -eq 200) {
    Write-Host "✅ Authentication working"
} else {
    Write-Host "❌ Authentication broken"
    exit 1
}

# 3. Database connectivity
$accountsResponse = Invoke-WebRequest -Uri "http://$prodEndpoint/api/accounting/balance" `
    -Headers @{ "Authorization" = "Bearer $token" }

if ($accountsResponse.StatusCode -eq 200) {
    Write-Host "✅ Database working"
} else {
    Write-Host "❌ Database failed"
    exit 1
}

Write-Host "✅ PRODUCTION DEPLOYMENT VERIFIED"
```

**Step 4: Post-Deployment Monitoring** (First 2 hours)

```powershell
# Monitor key metrics every 15 minutes

function Get-ProdMetrics {
    $region = "us-east-1"
    
    # Error rate
    $errorRate = aws cloudwatch get-metric-statistics `
        --namespace AWS/ApplicationELB `
        --metric-name HTTPCode_Target_5XX_Count `
        --start-time (Get-Date).AddMinutes(-15).ToUniversalTime() `
        --end-time (Get-Date).ToUniversalTime() `
        --period 900 `
        --statistics Sum
    
    Write-Host "Error Rate (5xx): $($errorRate.Datapoints[0].Sum)"
    
    # Response time (latency)
    $latency = aws cloudwatch get-metric-statistics `
        --namespace AWS/ApplicationELB `
        --metric-name TargetResponseTime `
        --start-time (Get-Date).AddMinutes(-15).ToUniversalTime() `
        --end-time (Get-Date).ToUniversalTime() `
        --period 900 `
        --statistics Average
    
    Write-Host "Avg Response Time: $($latency.Datapoints[0].Average)s"
    
    # Active connections
    $connections = aws cloudwatch get-metric-statistics `
        --namespace AWS/ApplicationELB `
        --metric-name ActiveConnectionCount `
        --start-time (Get-Date).AddMinutes(-15).ToUniversalTime() `
        --end-time (Get-Date).ToUniversalTime() `
        --period 900 `
        --statistics Sum
    
    Write-Host "Active Connections: $($connections.Datapoints[0].Sum)"
}

# Monitor every 15 minutes for 2 hours
for ($i = 0; $i -lt 8; $i++) {
    Write-Host "[$i/8] Monitoring metrics..."
    Get-ProdMetrics
    Start-Sleep -Seconds 900  # 15 minutes
}

Write-Host "✅ 2-hour monitoring window complete - Patch stable"
```

---

## Part 4: Rollback Procedures

### 4.1 Local Rollback

```powershell
# If patch breaks local deployment:

# 1. Identify last known good commit
git log --oneline

# 2. Revert to previous commit
git revert <bad-commit-hash>
# OR
git reset --hard <good-commit-hash>

# 3. Stop and remove containers
docker compose -f auth-service/docker-compose.dev.yml down
docker compose -f accounting-service/docker-compose.yml down
docker compose -f bridge/docker-compose.yml down
docker compose -f flowise-proxy-service-py/docker-compose.yml down

# 4. Remove failed images
docker rmi auth-service:patch accounting-service:patch bridge:patch flowise-proxy:patch

# 5. Rebuild and restart
.\automated_setup.bat

Write-Host "✅ Local rollback complete"
```

### 4.2 AWS Rollback

#### **Option 1: Revert to Previous Docker Image (Fastest)**

```powershell
# If ECS deployment is causing issues (most common)

# Get current task definition
$taskDefArn = aws ecs describe-services `
    --cluster chatproxy-prod-cluster `
    --services auth-service `
    --query 'services[0].taskDefinition' `
    --output text

# Get previous task definition
$prevTaskDef = aws ecs describe-task-definition `
    --task-definition $taskDefArn `
    --query 'taskDefinition.containerDefinitions[0].image'

# Update service to use previous image
aws ecs update-service `
    --cluster chatproxy-prod-cluster `
    --service auth-service `
    --task-definition auth-service:OLD_REVISION_NUMBER

Write-Host "⏳ ECS is rolling back to previous image..."
```

#### **Option 2: Git Revert (Clean Rollback)**

```powershell
# Recommended for permanent rollback

# 1. Revert the merge
git revert -m 1 <bad-merge-commit>

# 2. Push to trigger new deployment
git push origin release/aws

# 3. GitHub Actions will automatically:
#    - Build new Docker images (from reverted code)
#    - Update ECR
#    - Redeploy ECS services

Write-Host "⏳ GitHub Actions redeployment initiated..."
```

#### **Option 3: Terraform Destruction (Nuclear)**

```powershell
# Only if infrastructure is corrupted beyond repair

cd infra/environments/prod

# 1. Backup current state
terraform state pull > backup.tfstate

# 2. Destroy infrastructure
terraform destroy -var-file=terraform.tfvars -auto-approve

# 3. Redeploy from previous stable release
git checkout <stable-commit>
terraform apply -var-file=terraform.tfvars

Write-Host "⚠️ Full infrastructure rollback complete"
```

---

## Part 5: Deployment Checklist Template

**Create `DEPLOYMENT_LOG_[DATE].md`:**

```markdown
# Deployment Log - [TICKET_ID] - [DATE]

## Pre-Deployment
- [ ] Code review completed
- [ ] All unit tests passing (npm test)
- [ ] All lint checks passing (npm run lint)
- [ ] Docker images build successfully
- [ ] Local integration tests pass
- [ ] Local smoke tests pass
- [ ] Change log created and reviewed

## LOCAL DEPLOYMENT
- [ ] Code merged to main
- [ ] Tag created: v1.x.x
- [ ] All services restarted successfully
- [ ] Health checks passing
- [ ] Smoke tests passing
- [ ] Deployed at: [HH:MM UTC]
- [ ] Deployed by: [Name]

## DEV DEPLOYMENT
- [ ] Code pushed to release/aws
- [ ] GitHub Actions workflow triggered
- [ ] Docker images built and pushed to ECR
- [ ] Terraform plan executed
- [ ] Terraform apply executed
- [ ] ECS services updated
- [ ] Deployed at: [HH:MM UTC]
- [ ] ALB endpoint: [URL]
- [ ] Integration tests passing
- [ ] Monitoring period: [24 hours]
- [ ] Status: ✅ APPROVED FOR STAGING

## STAGING DEPLOYMENT
- [ ] Release branch created
- [ ] Staging workflow triggered
- [ ] Deployed at: [HH:MM UTC]
- [ ] ALB endpoint: [URL]
- [ ] Integration tests passing
- [ ] Soak test duration: [24 hours]
- [ ] CloudWatch logs reviewed
- [ ] Performance metrics acceptable
- [ ] Status: ✅ APPROVED FOR PRODUCTION

## PRODUCTION DEPLOYMENT
- [ ] Production approval received from: [Name]
- [ ] Maintenance window announced to users
- [ ] On-call engineer: [Name]
- [ ] Deployed at: [HH:MM UTC]
- [ ] ALB endpoint: [URL]
- [ ] Blue-green deployment initiated
- [ ] Rolling update progress: [0%, 25%, 50%, 75%, 100%]
- [ ] All health checks passing
- [ ] Post-deployment monitoring: ✅
- [ ] Error rate acceptable: [%]
- [ ] Latency acceptable: [ms]
- [ ] Status: ✅ PRODUCTION LIVE

## Rollback (if needed)
- [ ] Issue detected at: [HH:MM UTC]
- [ ] Rollback initiated at: [HH:MM UTC]
- [ ] Rollback method: [Image revert / Git revert / Full rebuild]
- [ ] Services recovered at: [HH:MM UTC]
- [ ] Root cause analysis: [Description]
- [ ] Ticket created: [TICKET_ID]

## Post-Deployment (24 hours later)
- [ ] All systems stable
- [ ] User reports: [None / List issues]
- [ ] Database health: ✅
- [ ] Backup completion verified
- [ ] Incident report: [Link to ticket]
- [ ] Deployment concluded: ✅
```

---

## Part 6: Quick Reference Commands

### Local
```powershell
# Check services
docker ps --format "table {{.Names}}\t{{.Status}}"

# View logs (all services)
docker compose -f auth-service/docker-compose.dev.yml logs -f
docker compose -f accounting-service/docker-compose.yml logs -f
docker compose -f bridge/docker-compose.yml logs -f
docker compose -f flowise-proxy-service-py/docker-compose.yml logs -f

# Restart all
docker compose -f auth-service/docker-compose.dev.yml restart
docker compose -f accounting-service/docker-compose.yml restart
docker compose -f bridge/docker-compose.yml restart
docker compose -f flowise-proxy-service-py/docker-compose.yml restart

# Full stop & start
docker compose -f auth-service/docker-compose.dev.yml down -v
docker compose -f accounting-service/docker-compose.yml down -v
docker compose -f bridge/docker-compose.yml down -v
docker compose -f flowise-proxy-service-py/docker-compose.yml down -v
```

### AWS (Dev/Staging/Prod)
```powershell
# View deployment status
aws ecs describe-services `
    --cluster chatproxy-[ENV]-cluster `
    --services auth-service accounting-service flowise-proxy bridge

# View logs
aws logs tail /chatproxy/[dev|staging|prod]/auth-service --follow
aws logs tail /chatproxy/[dev|staging|prod]/accounting-service --follow

# Get ALB endpoint
cd infra/environments/[dev|staging|prod]
terraform output -raw alb_dns_name

# Manually trigger rolling update (force redeployment)
aws ecs update-service `
    --cluster chatproxy-prod-cluster `
    --service auth-service `
    --force-new-deployment
```

---

## Part 7: Disaster Recovery

### Complete Service Failure

```powershell
# Step 1: Stop all public traffic
aws elbv2 deregister-targets `
    --target-group-arn <target-group-arn> `
    --targets Id=<instance-id> `
    --region us-east-1

# Step 2: Isolate database
aws rds stop-db-instance --db-instance-identifier accounting-db-prod

# Step 3: Restore from backup
aws rds restore-db-instance-from-db-snapshot `
    --db-instance-identifier accounting-db-prod-restored `
    --db-snapshot-identifier <snapshot-arn>

# Step 4: Update DNS/ALB to point to restored infrastructure
aws route53 change-resource-record-sets ...

# Step 5: Gradually enable traffic
for ($i = 1; $i -le 100; $i += 10) {
    # Register targets with increasing weight
    aws elbv2 register-targets `
        --target-group-arn <target-group-arn> `
        --targets Id=<instance-id> `
        --region us-east-1
    Start-Sleep -Seconds 60
}
```

---

## Summary: Patching Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. LOCAL DEVELOPMENT                                            │
│    • Code changes + unit tests                                  │
│    • Docker build verification                                  │
│    • Local integration tests (docker-compose)                   │
│    • Smoke tests & manual QA                                    │
│    • Git commit & push to main                                  │
└────────────────↓────────────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────────────┐
│ 2. DEV DEPLOYMENT (Automated via GitHub Actions)                │
│    • Merge main → release/aws                                   │
│    • Build Docker images → ECR                                  │
│    • Terraform plan                                             │
│    • Terraform apply → ECS update (3 instances)                 │
│    • Integration tests + Monitoring (24 hours)                  │
└────────────────▼────────────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────────────┐
│ 3. STAGING DEPLOYMENT (Automated via GitHub Actions)            │
│    • Create release branch                                      │
│    • Deploy to staging (same as dev, smaller scale)             │
│    • Soak test + monitoring (24+ hours)                         │
│    • Performance validation                                     │
└────────────────▼────────────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────────────┐
│ 4. PRODUCTION DEPLOYMENT (Manual Approval)                      │
│    • Blue-green deployments                                     │
│    • Zero-downtime rolling update                               │
│    • ALB health checks                                          │
│    • Post-deployment monitoring (2 hours)                       │
│    • Rollback plan ready                                        │
└────────────────▼────────────────────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────────────────────┐
│ 5. INCIDENT RESPONSE (If needed)                                │
│    • Immediate rollback if needed                               │
│    • Root cause analysis                                        │
│    • Patch redeployment after fix                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Checklist

- [ ] Create patch classification in your project
- [ ] Set up GitHub Actions workflows for each environment
- [ ] Create deployment approval gates in GitHub
- [ ] Configure CloudWatch alarms + SNS notifications
- [ ] Document on-call runbook for each environment
- [ ] Create Slack/email notifications on deployment
- [ ] Test rollback procedures monthly
- [ ] Schedule regular security patch review
- [ ] Document known issues + workarounds
- [ ] Train team on this patching strategy
