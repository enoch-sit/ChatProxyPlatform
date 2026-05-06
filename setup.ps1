#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ChatProxyPlatform -- Consolidated Setup Script for Windows Workstations.

.DESCRIPTION
    Single entry point for fresh machine setup. Replaces:
      quick_install.bat, automated_setup.bat, setup_env_files.bat,
      generate_secrets.bat, configure_drives.bat, configure_flowise_api.bat,
      check_drives_and_setup.bat

    Steps:
      1. Check/install prerequisites (Docker, Node.js, Python, Git)
      2. Detect optimal drive layout
      3. Generate secrets and .env files
      4. Configure drives (optional)
      5. Start all services in dependency order
      6. Run health checks

.PARAMETER SkipPrereqs
    Skip prerequisite installation (assume already installed).

.PARAMETER SkipDriveConfig
    Skip drive detection and configuration (use defaults).

.PARAMETER SkipFlowise
    Skip Flowise service startup.

.PARAMETER Unattended
    Run without interactive prompts (use defaults for everything).

.EXAMPLE
    .\setup.ps1                        # Full interactive setup
    .\setup.ps1 -SkipPrereqs           # Skip prerequisite install
    .\setup.ps1 -Unattended            # Non-interactive (CI/scripted use)
#>
[CmdletBinding()]
param(
    [switch]$SkipPrereqs,
    [switch]$SkipDriveConfig,
    [switch]$SkipFlowise,
    [switch]$Unattended
)

$ErrorActionPreference = "Stop"
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ─── Helpers ──────────────────────────────────────────────────────────────────
function Write-Step {
    param([int]$Step, [int]$Total, [string]$Message)
    Write-Host "`n[$Step/$Total] $Message" -ForegroundColor Cyan
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

function Test-Command { param([string]$Cmd) return [bool](Get-Command $Cmd -ErrorAction SilentlyContinue) }

function Test-ServiceHealth {
    param([string]$Name, [int]$Port, [string]$Path = "/health", [int]$Retries = 5)
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$Port$Path" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($r.StatusCode -eq 200) {
                Write-OK "$Name is healthy (port $Port)"
                return $true
            }
        } catch { }
        if ($i -lt $Retries) { Start-Sleep -Seconds 3 }
    }
    Write-Warn "$Name not responding on port $Port (may still be starting)"
    return $false
}

# ─── Banner ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  ChatProxyPlatform -- Workstation Setup" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  Machine : $env:COMPUTERNAME"
Write-Host "  User    : $env:USERNAME"
Write-Host "  Date    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "  Dir     : $scriptRoot"
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""

$totalSteps = 6
$step = 0

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Prerequisites
# ═══════════════════════════════════════════════════════════════════════════════
$step++
Write-Step $step $totalSteps "Checking prerequisites..."

$prereqs = @{
    "docker"  = @{ Check = "docker"; Install = "Docker.DockerDesktop"; Version = "docker --version" }
    "node"    = @{ Check = "node";   Install = "OpenJS.NodeJS.LTS";    Version = "node --version" }
    "python"  = @{ Check = "python"; Install = "Python.Python.3.12";   Version = "python --version" }
    "git"     = @{ Check = "git";    Install = "Git.Git";              Version = "git --version" }
}

$missing = @()
foreach ($name in $prereqs.Keys) {
    $p = $prereqs[$name]
    if (Test-Command $p.Check) {
        $ver = & $p.Check --version 2>&1 | Select-Object -First 1
        Write-OK "$name : $ver"
    } else {
        Write-Warn "$name is not installed"
        $missing += $name
    }
}

if ($missing.Count -gt 0 -and -not $SkipPrereqs) {
    if (-not (Test-Command "winget")) {
        Write-Fail "winget not available. Please install manually: $($missing -join ', ')"
        Write-Host "  Docker Desktop: https://www.docker.com/products/docker-desktop/"
        Write-Host "  Node.js LTS:    https://nodejs.org/"
        Write-Host "  Python 3.12+:   https://www.python.org/downloads/"
        Write-Host "  Git:            https://git-scm.com/downloads/"
        exit 1
    }

    foreach ($name in $missing) {
        $p = $prereqs[$name]
        Write-Host "  Installing $name via winget..." -ForegroundColor Yellow
        winget install -e --id $p.Install --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$name installation may have failed -- check manually"
        } else {
            Write-OK "$name installed"
        }
    }

    if ($missing -contains "docker") {
        Write-Host ""
        Write-Host "  IMPORTANT: Docker Desktop was just installed." -ForegroundColor Yellow
        Write-Host "  Please restart your computer, start Docker Desktop," -ForegroundColor Yellow
        Write-Host "  then re-run this script." -ForegroundColor Yellow
        exit 0
    }
}

# Verify Docker daemon is running
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker daemon is not running. Start Docker Desktop and retry."
    exit 1
}
Write-OK "Docker daemon is running"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Drive configuration (optional)
# ═══════════════════════════════════════════════════════════════════════════════
$step++
Write-Step $step $totalSteps "Checking drive configuration..."

if ($SkipDriveConfig) {
    Write-OK "Skipped (using defaults)"
} else {
    $configureDrivesScript = Join-Path $scriptRoot "scripts\archive\configure_drives.py"
    if (-not (Test-Path $configureDrivesScript)) {
        $configureDrivesScript = Join-Path $scriptRoot "configure_drives.py"
    }
    if (Test-Path $configureDrivesScript) {
        # Check if D: drive exists (common for multi-disk setups)
        if (Test-Path "D:\") {
            if (Test-Command "python") {
                Write-Host "  D: drive detected. Running drive configuration..." -ForegroundColor Yellow
                python $configureDrivesScript 2>&1 | ForEach-Object { Write-Host "  $_" }
            } else {
                Write-OK "D: drive detected but Python not available -- skipping drive config (using defaults)"
            }
        } else {
            Write-OK "Single drive setup -- using defaults"
        }
    } else {
        Write-OK "No drive configuration script found -- using defaults"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Generate secrets and .env files
# ═══════════════════════════════════════════════════════════════════════════════
$step++
Write-Step $step $totalSteps "Generating secrets and .env files..."

$generateSecretsPs1 = Join-Path $scriptRoot "scripts\generate-secrets.ps1"
if (Test-Path $generateSecretsPs1) {
    & $generateSecretsPs1 -WorkspaceRoot $scriptRoot
    if ($LASTEXITCODE -eq 0 -or $?) {
        Write-OK "Secrets generated and .env files updated"
    } else {
        Write-Warn "Secret generation had issues -- check output above"
    }
} else {
    Write-Warn "generate-secrets.ps1 not found -- creating .env from templates only"
    # Fallback: copy .env.example files
    $services = @("auth-service", "accounting-service", "flowise-proxy-service-py", "bridge", "flowise")
    foreach ($svc in $services) {
        $envExample = Join-Path $scriptRoot "$svc\.env.example"
        $envFile = Join-Path $scriptRoot "$svc\.env"
        if ((Test-Path $envExample) -and -not (Test-Path $envFile)) {
            Copy-Item $envExample $envFile
            Write-OK "Created $svc/.env from template"
        }
    }
}

# Safety net: ensure FLOWISE_SECRETKEY_OVERWRITE is set (prevents API key
# invalidation on Flowise restart).
$flowiseEnv = Join-Path $scriptRoot "flowise\.env"
if (Test-Path $flowiseEnv) {
    $flowiseEnvContent = Get-Content $flowiseEnv -Raw
    if ($flowiseEnvContent -notmatch 'FLOWISE_SECRETKEY_OVERWRITE=\S+') {
        $bytes = [byte[]]::new(24)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
        $generatedKey = [Convert]::ToBase64String($bytes)
        Add-Content -Path $flowiseEnv -Value "`nFLOWISE_SECRETKEY_OVERWRITE=$generatedKey"
        Write-OK "Generated FLOWISE_SECRETKEY_OVERWRITE (prevents API key invalidation on restart)"
    } else {
        Write-OK "FLOWISE_SECRETKEY_OVERWRITE is set"
    }
} else {
    Write-Warn "flowise/.env not found -- FLOWISE_SECRETKEY_OVERWRITE cannot be verified"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Start services in dependency order
# ═══════════════════════════════════════════════════════════════════════════════
$step++
Write-Step $step $totalSteps "Starting services..."

# Read deploy order from workstation manifest
$manifest = Get-Content (Join-Path $scriptRoot "workstation-manifest.json") -Raw | ConvertFrom-Json
$deployOrder = $manifest.deployOrder

# Map service names to source directories
$svcDirs = @{
    "auth-service"       = "auth-service"
    "accounting-service" = "accounting-service"
    "flowise"            = "flowise"
    "flowise-proxy"      = "flowise-proxy-service-py"
    "bridge"             = "bridge"
}

$errors = @()
foreach ($svc in $deployOrder) {
    if ($svc -eq "flowise" -and $SkipFlowise) {
        Write-Host "  Skipping flowise" -ForegroundColor DarkGray
        continue
    }

    $dir = $svcDirs[$svc]
    $svcManifest = $manifest.services.$svc
    $composeFile = $svcManifest.composeFile

    $composePath = Join-Path $scriptRoot "$dir\$composeFile"
    if (-not (Test-Path $composePath)) {
        Write-Warn "Compose file not found: $dir/$composeFile -- skipping $svc"
        continue
    }

    Write-Host "  Starting $svc..." -ForegroundColor Yellow
    Push-Location (Join-Path $scriptRoot $dir)
    $savedEAP = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    docker compose -f $composeFile up -d 2>&1 | Out-Null
    $dockerExit = $LASTEXITCODE
    $ErrorActionPreference = $savedEAP
    if ($dockerExit -ne 0) {
        Write-Fail "$svc failed to start"
        $errors += $svc
    } else {
        Write-OK "$svc started"
    }
    Pop-Location
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Flowise API key (interactive)
# ═══════════════════════════════════════════════════════════════════════════════
$step++
Write-Step $step $totalSteps "Configuring Flowise API key..."

if ($SkipFlowise) {
    Write-OK "Skipped (Flowise disabled)"
} else {
    $proxyEnv = Join-Path $scriptRoot "flowise-proxy-service-py\.env"
    $hasApiKey = $false
    if (Test-Path $proxyEnv) {
        $content = Get-Content $proxyEnv -Raw
        if ($content -match 'FLOWISE_API_KEY=\S+') { $hasApiKey = $true }
    }

    if ($hasApiKey) {
        Write-OK "Flowise API key already configured"
    } elseif ($Unattended) {
        Write-Warn "Flowise API key not set -- configure later in Bridge Admin > Settings"
        Write-Host "    http://localhost:3082  (Admin tab: Settings > Flowise API Key)" -ForegroundColor DarkGray
    } else {
        Write-Host ""
        Write-Host "  Flowise should now be running at http://localhost:3002" -ForegroundColor Yellow
        Write-Host "  1. Open Flowise in your browser" -ForegroundColor Yellow
        Write-Host "  2. Go to Settings > API Keys > Create new key" -ForegroundColor Yellow
        Write-Host "  3. Paste the key below (or set it later in Bridge Admin > Settings)" -ForegroundColor Yellow
        Write-Host ""
        $apiKey = Read-Host "  Enter Flowise API key (or press Enter to skip)"
        if ($apiKey) {
            $configScript = Join-Path $scriptRoot "configure_flowise_api.py"
            if (Test-Path $configScript) {
                echo $apiKey | python $configScript 2>&1 | ForEach-Object { Write-Host "  $_" }
            } else {
                # Direct write
                if (Test-Path $proxyEnv) {
                    $lines = Get-Content $proxyEnv
                    $updated = $false
                    $newLines = $lines | ForEach-Object {
                        if ($_ -match '^FLOWISE_API_KEY=') { $updated = $true; "FLOWISE_API_KEY=$apiKey" } else { $_ }
                    }
                    if (-not $updated) { $newLines += "FLOWISE_API_KEY=$apiKey" }
                    $newLines | Set-Content $proxyEnv
                }
            }
            Write-OK "API key configured"
        } else {
            Write-Warn "Skipped -- configure later in Bridge Admin > Settings"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Health checks
# ═══════════════════════════════════════════════════════════════════════════════
$step++
Write-Step $step $totalSteps "Running health checks..."

Write-Host "  Waiting 10 seconds for services to initialise..." -ForegroundColor DarkGray
Start-Sleep -Seconds 10

foreach ($svc in $deployOrder) {
    if ($svc -eq "flowise" -and $SkipFlowise) { continue }
    $svcManifest = $manifest.services.$svc
    Test-ServiceHealth -Name $svc -Port $svcManifest.port -Path $svcManifest.healthPath | Out-Null
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  Setup Complete" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""
Write-Host "  Service URLs:" -ForegroundColor White
Write-Host "    Bridge UI    : http://localhost:3082"
Write-Host "    Flowise      : http://localhost:3002"
Write-Host "    Proxy API    : http://localhost:8000"
Write-Host "    Auth API     : http://localhost:3000"
Write-Host "    Accounting   : http://localhost:3001"
Write-Host ""

if ($errors.Count -gt 0) {
    Write-Host "  Failed services: $($errors -join ', ')" -ForegroundColor Red
    Write-Host "  Run .\diagnose.ps1 for detailed diagnostics." -ForegroundColor Yellow
} else {
    Write-Host "  All services started successfully!" -ForegroundColor Green
}

# Record local version
$versionFile = Join-Path $scriptRoot "version.json"
if (Test-Path $versionFile) {
    $vData = Get-Content $versionFile -Raw | ConvertFrom-Json
    $localVersionFile = Join-Path $scriptRoot ".local-version"
    @{
        version    = $vData.version
        machine    = $env:COMPUTERNAME
        setupDate  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        gitSha     = (& git rev-parse --short HEAD 2>$null)
    } | ConvertTo-Json | Set-Content $localVersionFile
    Write-Host "  Version $($vData.version) recorded in .local-version" -ForegroundColor DarkGray
}

Write-Host ""
