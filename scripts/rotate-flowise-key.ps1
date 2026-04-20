#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Rotate the Flowise API key across AWS and/or Windows workstation.

.DESCRIPTION
    Updates the Flowise API key in:
      - AWS Secrets Manager (/chatproxy/dev/flowise/api-key)
      - ECS proxy service (force new deployment)
      - Local flowise-proxy-service-py/.env (Windows workstation)
      - Local proxy Docker container (recreate)

    The key itself must be created in the Flowise UI first:
      Flowise > Settings > API Keys > Create/regenerate

.PARAMETER Target
    Where to rotate: 'aws', 'local', or 'both' (default: both).

.PARAMETER Region
    AWS region (default: us-east-1).

.PARAMETER SkipVerify
    Skip the post-rotation verification step.

.EXAMPLE
    .\rotate-flowise-key.ps1                     # Rotate on AWS + local
    .\rotate-flowise-key.ps1 -Target aws         # AWS only
    .\rotate-flowise-key.ps1 -Target local       # Local workstation only
#>
[CmdletBinding()]
param(
    [ValidateSet('aws', 'local', 'both')]
    [string]$Target = 'both',

    [string]$Region = 'us-east-1',

    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSScriptRoot  # repo root (scripts/ is one level down)

function Write-OK   { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

# ── Banner ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Flowise API Key Rotation" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Target : $Target"
Write-Host "  Region : $Region"
Write-Host ""

# ── Collect new key (SecureString -- never shown on screen) ──────────
$secure = Read-Host -AsSecureString "Paste your new Flowise API key (input hidden)"
$bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$newKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if ([string]::IsNullOrWhiteSpace($newKey)) {
    Write-Fail "No key provided. Aborting."
    exit 1
}

$maskedKey = "$($newKey.Substring(0,4))...$($newKey.Substring($newKey.Length - 4))"
Write-Host "  Key    : $maskedKey (length=$($newKey.Length))" -ForegroundColor DarkGray
Write-Host ""

$errors = @()

# ═══════════════════════════════════════════════════════════════════════
# AWS: Secrets Manager + ECS redeploy
# ═══════════════════════════════════════════════════════════════════════
if ($Target -eq 'aws' -or $Target -eq 'both') {
    Write-Host "[1] Updating AWS Secrets Manager..." -ForegroundColor Cyan

    # Build JSON and write to temp file (avoids shell quoting issues)
    $json = [PSCustomObject]@{ FLOWISE_API_KEY = $newKey } | ConvertTo-Json -Compress
    $tmpFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpFile, $json, [System.Text.UTF8Encoding]::new($false))

    try {
        $env:PYTHONUTF8 = "1"
        aws secretsmanager put-secret-value `
            --region $Region `
            --secret-id /chatproxy/dev/flowise/api-key `
            --secret-string "file://$tmpFile" 2>$null

        if ($LASTEXITCODE -eq 0) {
            Write-OK "Secret /chatproxy/dev/flowise/api-key updated"
        } else {
            Write-Fail "Failed to update Secrets Manager"
            $errors += 'secrets-manager'
        }
    } finally {
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    }

    # Force new ECS deployment for the proxy
    Write-Host ""
    Write-Host "[2] Forcing ECS proxy redeployment..." -ForegroundColor Cyan

    $cluster = 'chatproxy-dev-cluster'
    $service = 'chatproxy-dev-flowise-proxy-service'

    aws ecs update-service `
        --region $Region `
        --cluster $cluster `
        --service $service `
        --force-new-deployment `
        --query 'service.deployments[0].{status:status,desired:desiredCount,running:runningCount}' `
        --output json 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-OK "ECS redeployment triggered for $service"
        Write-Host "  New tasks will pick up the key from Secrets Manager." -ForegroundColor DarkGray
    } else {
        Write-Fail "ECS redeployment failed"
        $errors += 'ecs-redeploy'
    }
}

# ═══════════════════════════════════════════════════════════════════════
# Local: .env + Docker restart
# ═══════════════════════════════════════════════════════════════════════
if ($Target -eq 'local' -or $Target -eq 'both') {
    Write-Host ""
    Write-Host "[3] Updating local .env..." -ForegroundColor Cyan

    $proxyEnv = Join-Path $scriptRoot "flowise-proxy-service-py\.env"
    if (Test-Path $proxyEnv) {
        $lines = Get-Content $proxyEnv
        $updated = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match '^FLOWISE_API_KEY=') { $updated = $true; "FLOWISE_API_KEY=$newKey" } else { $_ }
        }
        if (-not $updated) { $newLines += "FLOWISE_API_KEY=$newKey" }
        $newLines | Set-Content $proxyEnv
        Write-OK "flowise-proxy-service-py/.env updated"
    } else {
        Write-Fail "Proxy .env not found at $proxyEnv"
        $errors += 'local-env'
    }

    # Restart proxy container
    Write-Host ""
    Write-Host "[4] Restarting local proxy container..." -ForegroundColor Cyan

    $proxyDir = Join-Path $scriptRoot "flowise-proxy-service-py"
    if (Test-Path (Join-Path $proxyDir "docker-compose.yml")) {
        Push-Location $proxyDir
        docker compose up -d --force-recreate 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Proxy container restarted"
        } else {
            Write-Fail "Proxy container restart failed"
            $errors += 'local-restart'
        }
        Pop-Location
    } else {
        Write-Warn "No docker-compose.yml in proxy dir -- skip container restart"
    }
}

# ═══════════════════════════════════════════════════════════════════════
# Verify
# ═══════════════════════════════════════════════════════════════════════
if (-not $SkipVerify) {
    Write-Host ""
    Write-Host "[5] Verifying new key..." -ForegroundColor Cyan

    # Test against local Flowise if available
    try {
        $headers = @{ "Authorization" = "Bearer $newKey" }
        $r = Invoke-WebRequest -Uri "http://localhost:3000/api/v1/chatflows" -Headers $headers -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($r.StatusCode -eq 200) {
            Write-OK "Key verified against local Flowise (HTTP 200)"
        }
    } catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        if ($status -eq 401) {
            Write-Fail "Key REJECTED by local Flowise (401) -- is the key correct?"
            $errors += 'verify-local'
        } else {
            Write-Warn "Local Flowise not reachable (HTTP $status) -- skip local verification"
        }
    }
}

# ── Clear sensitive data ─────────────────────────────────────────────
$newKey = $null
$json = $null

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "======================================" -ForegroundColor Red
    Write-Host " Rotation completed with errors" -ForegroundColor Red
    Write-Host " Failed steps: $($errors -join ', ')" -ForegroundColor Red
    Write-Host "======================================" -ForegroundColor Red
    exit 1
} else {
    Write-Host "======================================" -ForegroundColor Green
    Write-Host " Rotation complete!" -ForegroundColor Green
    Write-Host "======================================" -ForegroundColor Green
    if ($Target -eq 'aws' -or $Target -eq 'both') {
        Write-Host "  ECS proxy will pick up the new key within ~5 minutes." -ForegroundColor DarkGray
    }
    Write-Host ""
}
