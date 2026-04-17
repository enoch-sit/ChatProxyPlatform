<#
.SYNOPSIS
    Start AWS dev environment -- bring all services back up for debugging.

.DESCRIPTION
    - Starts MongoDB EC2 instance and waits for it
    - Starts RDS instance and waits for it
    - Scales all ECS services to 1 task
    - Verifies ALB target health

.EXAMPLE
    .\infra\scripts\dev-start.ps1
    .\infra\scripts\dev-start.ps1 -SkipRds     # RDS already running
    .\infra\scripts\dev-start.ps1 -NoWait      # don't wait for healthy targets
#>

param(
    [switch]$SkipRds,
    [switch]$SkipMongodb,
    [switch]$SkipEcs,
    [switch]$NoWait,
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

$RdsInstanceId    = "chatproxy-dev-accounting-db"
$MongoInstanceTag = "chatproxy-dev-mongodb"

# ── MongoDB EC2: start ─────────────────────────────────────────
if (-not $SkipMongodb) {
    Write-Host "`n=== Starting MongoDB EC2: $MongoInstanceTag ===" -ForegroundColor Yellow
    $instanceId = aws ec2 describe-instances `
        --filters "Name=tag:Name,Values=$MongoInstanceTag" "Name=instance-state-name,Values=stopped" `
        --query "Reservations[0].Instances[0].InstanceId" `
        --output text `
        --region $Region 2>$null

    if ($instanceId -and $instanceId -ne "None") {
        aws ec2 start-instances `
            --instance-ids $instanceId `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host "  EC2 $instanceId starting..." -ForegroundColor Green

        if (-not $NoWait) {
            Write-Host "  Waiting for EC2 running status..." -NoNewline
            aws ec2 wait instance-running `
                --instance-ids $instanceId `
                --region $Region
            Write-Host " ready" -ForegroundColor Green
        }
    } else {
        $runningId = aws ec2 describe-instances `
            --filters "Name=tag:Name,Values=$MongoInstanceTag" "Name=instance-state-name,Values=running" `
            --query "Reservations[0].Instances[0].InstanceId" `
            --output text `
            --region $Region 2>$null
        if ($runningId -and $runningId -ne "None") {
            Write-Host "  Already running: $runningId" -ForegroundColor DarkYellow
        } else {
            Write-Host "  No stopped MongoDB instance found" -ForegroundColor Red
        }
    }
}

# ── RDS: start ─────────────────────────────────────────────────
if (-not $SkipRds) {
    Write-Host "`n=== Starting RDS instance: $RdsInstanceId ===" -ForegroundColor Yellow
    $rdsStatus = (aws rds describe-db-instances `
        --db-instance-identifier $RdsInstanceId `
        --region $Region `
        --query "DBInstances[0].DBInstanceStatus" `
        --output text 2>$null)

    if ($rdsStatus -eq "stopped") {
        aws rds start-db-instance `
            --db-instance-identifier $RdsInstanceId `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host "  RDS starting..." -ForegroundColor Green

        if (-not $NoWait) {
            Write-Host "  Waiting for RDS available (this takes a few minutes)..." -NoNewline
            aws rds wait db-instance-available `
                --db-instance-identifier $RdsInstanceId `
                --region $Region
            Write-Host " ready" -ForegroundColor Green
        }
    } else {
        Write-Host "  RDS status: $rdsStatus (skipping start)" -ForegroundColor DarkYellow
    }
}

# ── ECS: scale to 1 ───────────────────────────────────────────
if (-not $SkipEcs) {
    Write-Host "`n=== Scaling ECS services to 1 ===" -ForegroundColor Yellow

    foreach ($svc in $PlatformServices) {
        Write-Host "  Scaling $svc -> 1 ..." -NoNewline
        aws ecs update-service `
            --cluster $PlatformCluster `
            --service $svc `
            --desired-count 1 `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host " done" -ForegroundColor Green
    }

    foreach ($svc in $FlowiseServices) {
        Write-Host "  Scaling $svc -> 1 ..." -NoNewline
        aws ecs update-service `
            --cluster $FlowiseCluster `
            --service $svc `
            --desired-count 1 `
            --region $Region `
            --no-cli-pager | Out-Null
        Write-Host " done" -ForegroundColor Green
    }
}

# ── Wait for healthy targets ──────────────────────────────────
if (-not $NoWait -and -not $SkipEcs) {
    Write-Host "`n=== Waiting for ECS services to stabilize ===" -ForegroundColor Yellow

    foreach ($svc in $PlatformServices) {
        Write-Host "  Waiting for $svc ..." -NoNewline
        aws ecs wait services-stable `
            --cluster $PlatformCluster `
            --services $svc `
            --region $Region 2>$null
        Write-Host " stable" -ForegroundColor Green
    }

    foreach ($svc in $FlowiseServices) {
        Write-Host "  Waiting for $svc ..." -NoNewline
        aws ecs wait services-stable `
            --cluster $FlowiseCluster `
            --services $svc `
            --region $Region 2>$null
        Write-Host " stable" -ForegroundColor Green
    }
}

Write-Host "`n=== Dev environment started ===" -ForegroundColor Cyan
Write-Host "Platform: https://aidcec-ai-agent.com" -ForegroundColor Cyan
Write-Host "Flowise:  https://flowise.aidcec-ai-agent.com" -ForegroundColor Cyan
Write-Host "Run .\infra\scripts\dev-stop.ps1 when done to save cost." -ForegroundColor Cyan
