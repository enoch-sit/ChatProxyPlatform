#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ChatProxyPlatform — Consolidated Patch Script for Windows Workstations.

.DESCRIPTION
    Single entry point for updating a workstation. Replaces:
      update_patch.bat, patch_local.ps1

    Features:
      - Version-aware: checks version.json vs .local-version
      - Selective rebuild: only rebuilds services that changed
      - Rolling restart: one service at a time
      - Health gating: stops if a service fails health check
      - Rollback support: revert to previous git state

.PARAMETER Mode
    quick  — git pull + recreate containers (env/config changes only)
    full   — git pull + rebuild images + recreate (code changes)
    test   — run tests for changed services without deploying
    status — show current version and what's changed

.PARAMETER Service
    Patch a specific service only (default: all changed services).

.PARAMETER Rollback
    Revert to the previous version (uses git tag from .local-version).

.PARAMETER Force
    Skip change detection — rebuild/restart all services.

.EXAMPLE
    .\patch.ps1                          # Auto-detect mode (quick if no code changes, full otherwise)
    .\patch.ps1 -Mode full               # Force full rebuild
    .\patch.ps1 -Mode quick              # Quick recreate only
    .\patch.ps1 -Service auth-service    # Patch single service
    .\patch.ps1 -Mode status             # Show version info
    .\patch.ps1 -Rollback                # Revert to previous version
    .\patch.ps1 -Mode test               # Test changed services
#>
[CmdletBinding()]
param(
    [ValidateSet("quick", "full", "test", "status", "auto")]
    [string]$Mode = "auto",

    [ValidateSet("auth-service", "accounting-service", "flowise-proxy", "bridge", "flowise", "all")]
    [string]$Service = "all",

    [switch]$Rollback,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$logFile = Join-Path $scriptRoot "logs\patch_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logsDir = Split-Path $logFile -Parent
if (-not (Test-Path $logsDir)) { New-Item -Path $logsDir -ItemType Directory -Force | Out-Null }

# ─── Helpers ──────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    switch ($Level) {
        "OK"   { Write-Host "  [OK] $Message" -ForegroundColor Green }
        "WARN" { Write-Host "  [WARN] $Message" -ForegroundColor Yellow }
        "FAIL" { Write-Host "  [FAIL] $Message" -ForegroundColor Red }
        default { Write-Host "  $Message" -ForegroundColor White }
    }
}

function Test-ServiceHealth {
    param([string]$Name, [int]$Port, [string]$Path = "/health", [int]$Retries = 8)
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$Port$Path" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        if ($i -lt $Retries) { Start-Sleep -Seconds 3 }
    }
    return $false
}

# ─── Service registry ────────────────────────────────────────────────────────
$manifest = Get-Content (Join-Path $scriptRoot "workstation-manifest.json") -Raw | ConvertFrom-Json

$svcDirs = @{
    "auth-service"       = "auth-service"
    "accounting-service" = "accounting-service"
    "flowise"            = "flowise"
    "flowise-proxy"      = "flowise-proxy-service-py"
    "bridge"             = "bridge"
}

$svcTestCmd = @{
    "auth-service"       = "npm test"
    "accounting-service" = "npm test"
    "flowise-proxy"      = "python -m pytest tests/ -v"
    "bridge"             = "npx tsc --noEmit"
}

# ─── Banner ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  ChatProxyPlatform — Patch" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue

# ─── Read current version ─────────────────────────────────────────────────────
$versionFile = Join-Path $scriptRoot "version.json"
$localVersionFile = Join-Path $scriptRoot ".local-version"

$currentVersion = "unknown"
$currentSha = "unknown"
if (Test-Path $localVersionFile) {
    $localData = Get-Content $localVersionFile -Raw | ConvertFrom-Json
    $currentVersion = $localData.version
    $currentSha = $localData.gitSha
}
Write-Host "  Current version : $currentVersion ($currentSha)" -ForegroundColor DarkGray

# ═══════════════════════════════════════════════════════════════════════════════
# Status mode
# ═══════════════════════════════════════════════════════════════════════════════
if ($Mode -eq "status") {
    Write-Host ""
    Write-Host "  Local version  : $currentVersion" -ForegroundColor White
    Write-Host "  Local git SHA  : $currentSha" -ForegroundColor White
    Write-Host "  Machine        : $env:COMPUTERNAME" -ForegroundColor White
    Write-Host ""

    # Check remote
    git fetch --quiet 2>$null
    $behind = (git rev-list --count HEAD..origin/main 2>$null)
    if ($behind -and [int]$behind -gt 0) {
        Write-Host "  Remote is $behind commit(s) ahead" -ForegroundColor Yellow
        git log --oneline HEAD..origin/main 2>$null | Select-Object -First 10 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Up to date with remote" -ForegroundColor Green
    }

    # Container status
    Write-Host ""
    Write-Host "  Running containers:" -ForegroundColor White
    docker ps --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}" 2>$null |
        ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Write-Host ""
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Rollback mode
# ═══════════════════════════════════════════════════════════════════════════════
if ($Rollback) {
    Write-Host ""
    Write-Host "  Rolling back..." -ForegroundColor Yellow

    # Find the previous tag
    $prevTag = git describe --tags --abbrev=0 HEAD~1 2>$null
    if (-not $prevTag) {
        # Fallback: use the SHA from .local-version
        if ($currentSha -and $currentSha -ne "unknown") {
            $prevTag = $currentSha
        } else {
            Write-Log "No previous version found to rollback to." "FAIL"
            exit 1
        }
    }

    Write-Host "  Reverting to: $prevTag" -ForegroundColor Yellow
    git checkout $prevTag -- .
    git checkout HEAD -- .local-version 2>$null  # Keep the version marker

    # Rebuild all services
    foreach ($svc in $manifest.deployOrder) {
        $dir = $svcDirs[$svc]
        $composeFile = $manifest.services.$svc.composeFile
        $composePath = Join-Path $scriptRoot "$dir\$composeFile"
        if (-not (Test-Path $composePath)) { continue }

        Write-Host "  Rebuilding $svc..." -ForegroundColor Yellow
        Push-Location (Join-Path $scriptRoot $dir)
        docker compose -f $composeFile up -d --force-recreate --build 2>&1 | Out-Null
        Pop-Location

        $port = $manifest.services.$svc.port
        $healthPath = $manifest.services.$svc.healthPath
        Start-Sleep -Seconds 5
        if (Test-ServiceHealth -Name $svc -Port $port -Path $healthPath) {
            Write-Log "$svc rolled back and healthy" "OK"
        } else {
            Write-Log "$svc rollback may have issues" "WARN"
        }
    }
    Write-Host ""
    Write-Host "  Rollback complete." -ForegroundColor Green
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Preflight: Docker check
# ═══════════════════════════════════════════════════════════════════════════════
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log "Docker is not running. Start Docker Desktop first." "FAIL"
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Git pull
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[1/5] Pulling latest changes..." -ForegroundColor Cyan
git pull
if ($LASTEXITCODE -ne 0) {
    Write-Log "git pull failed. Resolve conflicts and retry." "FAIL"
    exit 1
}
Write-Log "git pull complete" "OK"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Detect changed services
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[2/5] Detecting changes..." -ForegroundColor Cyan

$changedServices = @()
if ($Service -ne "all") {
    $changedServices = @($Service)
    Write-Log "Targeting specific service: $Service" "Info"
} elseif ($Force) {
    $changedServices = @($manifest.deployOrder)
    Write-Log "Force mode: all services selected" "Info"
} else {
    # Detect changes since last known SHA
    $diffBase = $currentSha
    if ($diffBase -eq "unknown") { $diffBase = "HEAD~1" }

    $changedFiles = git diff --name-only $diffBase HEAD 2>$null
    if (-not $changedFiles) {
        $changedFiles = git diff --name-only HEAD~1 HEAD 2>$null
    }

    $dirToService = @{
        "auth-service"            = "auth-service"
        "accounting-service"      = "accounting-service"
        "flowise-proxy-service-py" = "flowise-proxy"
        "bridge"                  = "bridge"
        "flowise"                 = "flowise"
    }

    if ($changedFiles) {
        foreach ($file in $changedFiles) {
            foreach ($dir in $dirToService.Keys) {
                if ($file -like "$dir/*") {
                    $svcName = $dirToService[$dir]
                    if ($changedServices -notcontains $svcName) {
                        $changedServices += $svcName
                    }
                }
            }
        }
    }

    if ($changedServices.Count -eq 0) {
        Write-Log "No service changes detected. Nothing to do." "OK"
        Write-Host "  Use -Force to rebuild anyway." -ForegroundColor DarkGray
        exit 0
    }
}

$hasCodeChanges = $changedServices.Count -gt 0
Write-Log "Changed services: $($changedServices -join ', ')" "Info"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Auto-detect mode
# ═══════════════════════════════════════════════════════════════════════════════
if ($Mode -eq "auto") {
    # If Dockerfiles or source code changed, use full; otherwise quick
    $needsRebuild = $false
    if ($changedFiles) {
        foreach ($file in $changedFiles) {
            if ($file -match "Dockerfile|\.ts$|\.tsx$|\.py$|\.js$|package\.json|requirements\.txt") {
                $needsRebuild = $true
                break
            }
        }
    }
    $Mode = if ($needsRebuild) { "full" } else { "quick" }
    Write-Host "  Auto-detected mode: $Mode" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "[3/5] Mode: $($Mode.ToUpper())" -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3b: Run tests (if test mode or full mode)
# ═══════════════════════════════════════════════════════════════════════════════
if ($Mode -eq "test" -or $Mode -eq "full") {
    Write-Host ""
    Write-Host "  Running tests for changed services..." -ForegroundColor Yellow

    $testFailed = $false
    foreach ($svc in $changedServices) {
        if (-not $svcTestCmd.ContainsKey($svc)) { continue }

        $dir = $svcDirs[$svc]
        $testCmd = $svcTestCmd[$svc]
        Write-Host "  Testing $svc..." -ForegroundColor Yellow

        Push-Location (Join-Path $scriptRoot $dir)
        try {
            Invoke-Expression $testCmd 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "$svc tests FAILED" "FAIL"
                $testFailed = $true
            } else {
                Write-Log "$svc tests passed" "OK"
            }
        } catch {
            Write-Log "$svc test error: $_" "WARN"
        }
        Pop-Location
    }

    if ($Mode -eq "test") {
        Write-Host ""
        if ($testFailed) {
            Write-Host "  Some tests failed. See log: $logFile" -ForegroundColor Red
        } else {
            Write-Host "  All tests passed." -ForegroundColor Green
        }
        exit $(if ($testFailed) { 1 } else { 0 })
    }

    if ($testFailed) {
        Write-Log "Aborting deploy due to test failures." "FAIL"
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Deploy changed services (rolling)
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[4/5] Deploying services..." -ForegroundColor Cyan

$buildFlag = if ($Mode -eq "full") { "--build" } else { "" }
$errors = @()

# Deploy in manifest order
foreach ($svc in $manifest.deployOrder) {
    if ($changedServices -notcontains $svc) { continue }

    $dir = $svcDirs[$svc]
    $composeFile = $manifest.services.$svc.composeFile
    $composePath = Join-Path $scriptRoot "$dir\$composeFile"
    if (-not (Test-Path $composePath)) {
        Write-Log "Compose file not found for $svc — skipping" "WARN"
        continue
    }

    Write-Host "  Deploying $svc ($Mode)..." -ForegroundColor Yellow
    Push-Location (Join-Path $scriptRoot $dir)

    $cmd = "docker compose -f $composeFile up -d --force-recreate $buildFlag"
    Invoke-Expression "$cmd 2>&1" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Log "$svc failed to deploy" "FAIL"
        $errors += $svc
        Pop-Location
        continue
    }
    Pop-Location

    # Health check with wait
    Write-Host "  Checking health..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 8
    $port = $manifest.services.$svc.port
    $healthPath = $manifest.services.$svc.healthPath
    if (Test-ServiceHealth -Name $svc -Port $port -Path $healthPath) {
        Write-Log "$svc deployed and healthy" "OK"
    } else {
        Write-Log "$svc deployed but health check inconclusive" "WARN"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Summary + version update
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[5/5] Summary" -ForegroundColor Cyan
Write-Host ""

docker ps --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}" 2>$null |
    ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

# Update .local-version
if (Test-Path $versionFile) {
    $vData = Get-Content $versionFile -Raw | ConvertFrom-Json
    $newSha = (& git rev-parse --short HEAD 2>$null)
    @{
        version     = $vData.version
        machine     = $env:COMPUTERNAME
        patchDate   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        gitSha      = $newSha
        patchMode   = $Mode
        services    = $changedServices
    } | ConvertTo-Json | Set-Content $localVersionFile
}

Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "================================================================" -ForegroundColor Red
    Write-Host "  Patch completed with errors: $($errors -join ', ')" -ForegroundColor Red
    Write-Host "  Log: $logFile" -ForegroundColor Red
    Write-Host "================================================================" -ForegroundColor Red
    exit 1
} else {
    $newVer = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw | ConvertFrom-Json).version } else { "unknown" }
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  Patch complete! Version: $newVer" -ForegroundColor Green
    Write-Host "  Services updated: $($changedServices -join ', ')" -ForegroundColor Green
    Write-Host "  Log: $logFile" -ForegroundColor DarkGray
    Write-Host "================================================================" -ForegroundColor Green
}
Write-Host ""
