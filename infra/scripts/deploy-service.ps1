<#
.SYNOPSIS
    Build, tag, push, and deploy a versioned Docker image to ECS via Terraform.

.DESCRIPTION
    Automates the full release cycle for any platform service:
      1. Docker build from the service's source directory
      2. ECR push — versioned tag AND :latest
      3. Update infra/environments/<env>/terraform.tfvars with the new image URI
      4. terraform apply -target=<module>  →  new ECS task-definition revision  →  rolling deploy
      5. Wait for ECS service to reach a stable state
      6. Auto-rollback if health check fails (when -AutoRollback is set)

    WHY THIS MATTERS:
      :latest means ECS can't diff revisions. A versioned tag causes Terraform to
      create a new task-definition revision → ECS rolling deploy is triggered cleanly
      and the prior tag can be used to roll back at any time.

    ROLLBACK: Re-run with an earlier tag (the image must still exist in ECR):
      .\infra\scripts\deploy-service.ps1 -Service flowise-proxy -Tag v1.0.0

.PARAMETER Service
    Service to deploy. One of:
      flowise-proxy | auth-service | accounting-service | bridge

.PARAMETER Tag
    Image version tag, e.g. v1.2.3 or a git short-SHA.
    If omitted, auto-generates from version.json + git SHA.

.PARAMETER Environment
    Terraform environment subdirectory under infra/environments/ (default: dev).

.PARAMETER SkipTerraform
    Push the image and update tfvars but do NOT run terraform apply.

.PARAMETER DryRun
    Show what would happen without executing anything.

.PARAMETER AutoRollback
    If the ECS service fails to stabilise, automatically revert to the previous task definition.

.PARAMETER HealthTimeout
    Seconds to wait for ECS service to stabilise (default: 300).

.PARAMETER CommitTfvars
    After deploy, git commit the updated terraform.tfvars.

.EXAMPLE
    # Deploy flowise-proxy with auto-generated version tag
    .\infra\scripts\deploy-service.ps1 -Service flowise-proxy

    # Deploy auth-service with explicit tag + auto-rollback
    .\infra\scripts\deploy-service.ps1 -Service auth-service -Tag v1.1.0 -AutoRollback

    # Dry run — see what would happen
    .\infra\scripts\deploy-service.ps1 -Service bridge -DryRun

    # Deploy + commit tfvars to git
    .\infra\scripts\deploy-service.ps1 -Service auth-service -Tag v1.1.0 -CommitTfvars
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("flowise-proxy", "auth-service", "accounting-service", "bridge")]
    [string]$Service,

    [string]$Tag,

    [string]$Environment = "dev",

    [switch]$SkipTerraform,

    [switch]$DryRun,

    [switch]$AutoRollback,

    [int]$HealthTimeout = 300,

    [switch]$CommitTfvars
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Service registry ─────────────────────────────────────────────────────────
# EcsSuffix is the portion after "chatproxy-<env>-" in the ECS service name.
$registry = @{
    "flowise-proxy" = @{
        SourceDir  = "flowise-proxy-service-py"
        EcrRepo    = "chatproxy/flowise-proxy"
        TfVar      = "flowise_proxy_service_image"
        TfModule   = "module.flowise_proxy_ecs"
        EcsSuffix  = "flowise-proxy-service"
    }
    "auth-service" = @{
        SourceDir  = "auth-service"
        EcrRepo    = "chatproxy/auth-service"
        TfVar      = "auth_service_image"
        TfModule   = "module.auth_ecs"
        EcsSuffix  = "auth-service"
    }
    "accounting-service" = @{
        SourceDir  = "accounting-service"
        EcrRepo    = "chatproxy/accounting-service"
        TfVar      = "accounting_service_image"
        TfModule   = "module.accounting_ecs"
        EcsSuffix  = "accounting-service"
    }
    "bridge" = @{
        SourceDir  = "bridge"
        EcrRepo    = "chatproxy/bridge"
        TfVar      = "bridge_image"
        TfModule   = "module.bridge_ecs"
        EcsSuffix  = "bridge"
    }
}

$cfg        = $registry[$Service]
$ecsCluster = "chatproxy-${Environment}-cluster"
$ecsService = "chatproxy-${Environment}-$($cfg.EcsSuffix)"

# ─── Resolve paths ────────────────────────────────────────────────────────────
# Script lives at infra/scripts/ — two levels up is the repo root.
$repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$tfDir      = Join-Path $repoRoot "infra\environments\$Environment"
$tfvarsPath = Join-Path $tfDir    "terraform.tfvars"
$sourceDir  = Join-Path $repoRoot $cfg.SourceDir

foreach ($p in @($tfvarsPath, $sourceDir)) {
    if (-not (Test-Path $p)) { throw "Path not found: $p" }
}

# ─── Auto-generate tag from version.json if not provided ─────────────────────
if (-not $Tag) {
    $versionFile = Join-Path $repoRoot "version.json"
    if (Test-Path $versionFile) {
        $versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
        $svcVersion = $versionData.services.$Service
        if (-not $svcVersion) { $svcVersion = $versionData.version }
        $gitSha = (& git -C $repoRoot rev-parse --short HEAD 2>$null)
        if (-not $gitSha) { $gitSha = "unknown" }
        $Tag = "v${svcVersion}-${gitSha}"
        Write-Host "Auto-generated tag from version.json: $Tag" -ForegroundColor Cyan
    } else {
        throw "No -Tag provided and version.json not found. Provide a tag explicitly."
    }
}

# ─── Resolve AWS account + region ────────────────────────────────────────────
$region    = (aws configure get region 2>$null).Trim()
if (-not $region) { $region = "us-east-1" }
$accountId = (aws sts get-caller-identity --query Account --output text).Trim()

$ecrBase        = "${accountId}.dkr.ecr.${region}.amazonaws.com"
$fullRepo       = "$ecrBase/$($cfg.EcrRepo)"
$versionedImage = "${fullRepo}:${Tag}"
$latestImage    = "${fullRepo}:latest"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Service     : $Service"                         -ForegroundColor Cyan
Write-Host "  Tag         : $Tag"                             -ForegroundColor Cyan
Write-Host "  Environment : $Environment"                     -ForegroundColor Cyan
Write-Host "  Image       : $versionedImage"                  -ForegroundColor Cyan
if ($DryRun)       { Write-Host "  Mode        : DRY RUN"    -ForegroundColor Yellow }
if ($AutoRollback) { Write-Host "  AutoRollback: ON"         -ForegroundColor Yellow }
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] Would execute:" -ForegroundColor Yellow
    Write-Host "  1. ECR login to $ecrBase"
    Write-Host "  2. docker build -t $($cfg.EcrRepo):$Tag $sourceDir"
    Write-Host "  3. docker push $versionedImage"
    Write-Host "  4. Update $tfvarsPath : $($cfg.TfVar) = `"$versionedImage`""
    Write-Host "  5. terraform apply -target=$($cfg.TfModule)"
    if ($CommitTfvars) { Write-Host "  6. git commit terraform.tfvars" }
    Write-Host ""
    Write-Host "No changes made." -ForegroundColor Green
    exit 0
}

# ─── Record current task definition for rollback ─────────────────────────────
$previousTaskDef = $null
if ($AutoRollback) {
    try {
        $svcJson = aws ecs describe-services --cluster $ecsCluster --services $ecsService --region $region --output json 2>$null
        if ($svcJson) {
            $svcInfo = $svcJson | ConvertFrom-Json
            $previousTaskDef = $svcInfo.services[0].taskDefinition
            Write-Host "Recorded current task def for rollback: $previousTaskDef" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "Could not record current task definition. Rollback will not be available."
    }
}

# ─── Step 1: ECR login ────────────────────────────────────────────────────────
Write-Host "[1/5] Logging into ECR..." -ForegroundColor Yellow
aws ecr get-login-password --region $region |
    docker login --username AWS --password-stdin $ecrBase
if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }

# ─── Step 2: Docker build ─────────────────────────────────────────────────────
Write-Host "[2/5] Building Docker image..." -ForegroundColor Yellow
docker build -t "$($cfg.EcrRepo):$Tag" $sourceDir
if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }

# ─── Step 3: Tag + push versioned AND :latest ────────────────────────────────
Write-Host "[3/5] Tagging and pushing to ECR..." -ForegroundColor Yellow
docker tag "$($cfg.EcrRepo):$Tag" $versionedImage
docker tag "$($cfg.EcrRepo):$Tag" $latestImage
docker push $versionedImage ; if ($LASTEXITCODE -ne 0) { throw "Push of versioned image failed" }
docker push $latestImage    ; if ($LASTEXITCODE -ne 0) { throw "Push of :latest failed" }
Write-Host "  Pushed: $versionedImage" -ForegroundColor Green
Write-Host "  Pushed: $latestImage"    -ForegroundColor Green

# ─── Step 4: Update terraform.tfvars ─────────────────────────────────────────
Write-Host "[4/5] Updating terraform.tfvars..." -ForegroundColor Yellow
$tfVarName = $cfg.TfVar
$lines     = Get-Content $tfvarsPath
$updated   = $false

$newLines = $lines | ForEach-Object {
    if ($_ -match "^\s*$([regex]::Escape($tfVarName))\s*=") {
        $updated = $true
        "$tfVarName = `"$versionedImage`""
    } else {
        $_
    }
}

if (-not $updated) {
    Write-Warning "Variable '$tfVarName' not found in terraform.tfvars — file NOT changed."
} else {
    $newLines | Set-Content $tfvarsPath
    Write-Host "  $tfVarName = `"$versionedImage`"" -ForegroundColor Green
}

# ─── Step 5: Terraform apply ──────────────────────────────────────────────────
if ($SkipTerraform) {
    Write-Host "[5/5] Skipped (-SkipTerraform)." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "To finish the deploy, run:" -ForegroundColor Cyan
    Write-Host "  cd `"$tfDir`""
    Write-Host "  terraform apply -var-file=terraform.tfvars -target=$($cfg.TfModule)"
    exit 0
}

Write-Host "[5/5] Running terraform apply..." -ForegroundColor Yellow
Push-Location $tfDir
try {
    terraform apply -var-file=terraform.tfvars -target=$($cfg.TfModule) -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }
} finally {
    Pop-Location
}

# ─── Wait for ECS stable ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "Waiting for ECS service to stabilise (timeout ${HealthTimeout}s)..." -ForegroundColor Yellow
aws ecs wait services-stable `
    --cluster $ecsCluster `
    --services $ecsService `
    --region  $region

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "  DEPLOYED: $Service @ $Tag"                      -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green

    # ─── Commit tfvars ────────────────────────────────────────────────────────
    if ($CommitTfvars) {
        Write-Host ""
        Write-Host "Committing terraform.tfvars..." -ForegroundColor Yellow
        Push-Location $repoRoot
        try {
            git add $tfvarsPath
            git commit -m "deploy($Service): $Tag [skip ci]"
            Write-Host "Committed. Run 'git push' to sync." -ForegroundColor Green
        } catch {
            Write-Warning "git commit failed: $_"
        } finally {
            Pop-Location
        }
    }
} else {
    Write-Warning "ECS 'wait services-stable' timed out or failed."

    # ─── Auto-rollback ────────────────────────────────────────────────────────
    if ($AutoRollback -and $previousTaskDef) {
        Write-Host ""
        Write-Host "AUTO-ROLLBACK: Reverting to previous task definition..." -ForegroundColor Red
        Write-Host "  Previous: $previousTaskDef" -ForegroundColor Yellow
        aws ecs update-service `
            --cluster $ecsCluster `
            --service $ecsService `
            --task-definition $previousTaskDef `
            --region $region `
            --output text > $null

        Write-Host "Waiting for rollback to stabilise..." -ForegroundColor Yellow
        aws ecs wait services-stable `
            --cluster $ecsCluster `
            --services $ecsService `
            --region $region

        if ($LASTEXITCODE -eq 0) {
            Write-Host "Rollback successful. Service is running previous version." -ForegroundColor Green
        } else {
            Write-Host "CRITICAL: Rollback also failed. Manual intervention required." -ForegroundColor Red
        }
        exit 1
    } elseif ($AutoRollback) {
        Write-Host "Cannot rollback: no previous task definition was recorded." -ForegroundColor Red
        exit 1
    } else {
        Write-Host "Check the AWS console for deployment status." -ForegroundColor Yellow
        Write-Host "To rollback manually, re-run with an earlier tag." -ForegroundColor Yellow
    }
}
