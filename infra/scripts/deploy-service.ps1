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
    Tip: use  -Tag (git rev-parse --short HEAD)  in a bash-compatible shell,
    or   -Tag (& git rev-parse --short HEAD)      in PowerShell.

.PARAMETER Environment
    Terraform environment subdirectory under infra/environments/ (default: dev).

.PARAMETER SkipTerraform
    Push the image and update tfvars but do NOT run terraform apply.
    Useful when you want to review the plan first, then apply manually.

.EXAMPLE
    # Deploy flowise-proxy as v1.1.0
    .\infra\scripts\deploy-service.ps1 -Service flowise-proxy -Tag v1.1.0

    # Deploy auth-service tagged with the current git SHA
    .\infra\scripts\deploy-service.ps1 -Service auth-service -Tag (& git rev-parse --short HEAD)

    # Push image + update tfvars only (apply manually later)
    .\infra\scripts\deploy-service.ps1 -Service bridge -Tag v2.0.0 -SkipTerraform

    # Roll back flowise-proxy to a previously deployed version
    .\infra\scripts\deploy-service.ps1 -Service flowise-proxy -Tag v1.0.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("flowise-proxy", "auth-service", "accounting-service", "bridge")]
    [string]$Service,

    [Parameter(Mandatory)]
    [string]$Tag,

    [string]$Environment = "dev",

    [switch]$SkipTerraform
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
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

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
Write-Host "Waiting for ECS service to stabilise (timeout ~10 min)..." -ForegroundColor Yellow
aws ecs wait services-stable `
    --cluster $ecsCluster `
    --services $ecsService `
    --region  $region

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "  DEPLOYED: $Service @ $Tag"                      -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
} else {
    Write-Warning "ECS 'wait services-stable' timed out. Check the AWS console for deployment status."
}
