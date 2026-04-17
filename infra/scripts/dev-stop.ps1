<#
.SYNOPSIS
    Scale AWS dev environment to zero — stop all services to save cost.
    Run this when you're done debugging. Reduces cost from ~$176/mo to ~$52/mo.

.DESCRIPTION
    - Scales all ECS services to 0 tasks (Platform + Flowise clusters)
    - Stops RDS instance
    - Stops MongoDB EC2 instance

.EXAMPLE
    .\infra\scripts\dev-stop.ps1
    .\infra\scripts\dev-stop.ps1 -SkipRds   # keep RDS running
#>

param(
    [switch]$SkipRds,
    [switch]$SkipMongodb,
    [switch]$SkipEcs,
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

# ── Constants ──────────────────────────────────────────────────
$PlatformCluster = "chatproxy-dev-cluster"
$FlowiseCluster  = "chatproxy-dev-flowise-cluster"

$PlatformServices = @(
    "chatproxy-dev-auth-service",
    "chatproxy-dev-accounting-service",
    "chatproxy-dev-flowise-proxy-service",
    "chatproxy-dev-bridge"
)

$FlowiseServices = @(
    "chatproxy-dev-flowise-service"
)

$RdsInstanceId   = "chatproxy-dev-accounting-db"
$MongoInstanceTag = "chatproxy-dev-mongodb"

# ── ECS: scale to 0 ───────────────────────────────────────────
if (-not $SkipEcs) {
    Write-Host "`n=== Scaling ECS services to 0 ===" -ForegroundColor Yellow

    foreach ($svc in $PlatformServices) {
        Write-Host "  Scaling $svc -> 0 ..." -NoNewline
        aws ecs update-service `
            --cluster $PlatformCluster `
            --service $svc `
            --desired-count 0 `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host " done" -ForegroundColor Green
    }

    foreach ($svc in $FlowiseServices) {
        Write-Host "  Scaling $svc -> 0 ..." -NoNewline
        aws ecs update-service `
            --cluster $FlowiseCluster `
            --service $svc `
            --desired-count 0 `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host " done" -ForegroundColor Green
    }
}

# ── RDS: stop ──────────────────────────────────────────────────
if (-not $SkipRds) {
    Write-Host "`n=== Stopping RDS instance: $RdsInstanceId ===" -ForegroundColor Yellow
    $rdsStatus = (aws rds describe-db-instances `
        --db-instance-identifier $RdsInstanceId `
        --region $Region `
        --query "DBInstances[0].DBInstanceStatus" `
        --output text 2>$null)

    if ($rdsStatus -eq "available") {
        aws rds stop-db-instance `
            --db-instance-identifier $RdsInstanceId `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host "  RDS stopping..." -ForegroundColor Green
    } else {
        Write-Host "  RDS status: $rdsStatus (skipping)" -ForegroundColor DarkYellow
    }
}

# ── MongoDB EC2: stop ──────────────────────────────────────────
if (-not $SkipMongodb) {
    Write-Host "`n=== Stopping MongoDB EC2: $MongoInstanceTag ===" -ForegroundColor Yellow
    $instanceId = aws ec2 describe-instances `
        --filters "Name=tag:Name,Values=$MongoInstanceTag" "Name=instance-state-name,Values=running" `
        --query "Reservations[0].Instances[0].InstanceId" `
        --output text `
        --region $Region 2>$null

    if ($instanceId -and $instanceId -ne "None") {
        aws ec2 stop-instances `
            --instance-ids $instanceId `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host "  EC2 $instanceId stopping..." -ForegroundColor Green
    } else {
        Write-Host "  No running MongoDB instance found (skipping)" -ForegroundColor DarkYellow
    }
}

Write-Host "`n=== Dev environment stopped ===" -ForegroundColor Cyan
Write-Host "Estimated idle cost: ~`$52/month (ALBs + stopped storage)" -ForegroundColor Cyan
Write-Host "Run .\infra\scripts\dev-start.ps1 to resume." -ForegroundColor Cyan
