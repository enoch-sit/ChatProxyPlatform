#!/usr/bin/env pwsh
<#
.SYNOPSIS
    ChatProxyPlatform -- Consolidated Diagnostic Script for Windows Workstations.

.DESCRIPTION
    Single entry point for all diagnostics. Replaces:
      check_system.bat, diagnose_setup.bat, post-installation-check.bat,
      pull_and_scan.bat, diagnose_login_problems.bat, check_users.bat

    Runs a comprehensive check of:
      - Prerequisites (Docker, Node, Python, Git)
      - Docker daemon and containers
      - Service health endpoints
      - Port availability
      - .env file status
      - JWT secret synchronisation
      - MongoDB connectivity
      - User/admin verification (optional)

.PARAMETER Quick
    Run a quick health check only (containers + endpoints).

.PARAMETER Login
    Run login-specific diagnostics (auth flow, JWT, CORS).

.PARAMETER Users
    Show user list from MongoDB.

.PARAMETER Full
    Run every diagnostic (default).

.PARAMETER SaveLog
    Save output to a timestamped log file.

.EXAMPLE
    .\diagnose.ps1                    # Full diagnostic
    .\diagnose.ps1 -Quick             # Quick health check
    .\diagnose.ps1 -Login             # Login problem diagnostics
    .\diagnose.ps1 -Users             # List users from MongoDB
#>
[CmdletBinding()]
param(
    [switch]$Quick,
    [switch]$Login,
    [switch]$Users,
    [switch]$Full,
    [switch]$SaveLog
)

$ErrorActionPreference = "Continue"
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Default to Full if nothing specified
if (-not $Quick -and -not $Login -and -not $Users) { $Full = $true }

$logLines = @()
function Write-Diag {
    param([string]$Message, [string]$Level = "Info")
    $ts = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "OK"   { "[OK]  " }
        "WARN" { "[WARN]" }
        "FAIL" { "[FAIL]" }
        "HEAD" { "------" }
        default { "[INFO]" }
    }
    $line = "$ts $prefix $Message"
    $script:logLines += $line

    switch ($Level) {
        "OK"   { Write-Host "  [OK] $Message" -ForegroundColor Green }
        "WARN" { Write-Host "  [WARN] $Message" -ForegroundColor Yellow }
        "FAIL" { Write-Host "  [FAIL] $Message" -ForegroundColor Red }
        "HEAD" { Write-Host "`n  --- $Message ---" -ForegroundColor Cyan }
        default { Write-Host "  $Message" }
    }
}

function Test-Command { param([string]$Cmd) return [bool](Get-Command $Cmd -ErrorAction SilentlyContinue) }

# ─── Banner ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  ChatProxyPlatform -- Diagnostics" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  Machine : $env:COMPUTERNAME"
Write-Host "  Date    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Show version info
$localVersionFile = Join-Path $scriptRoot ".local-version"
if (Test-Path $localVersionFile) {
    $lv = Get-Content $localVersionFile -Raw | ConvertFrom-Json
    Write-Host "  Version : $($lv.version) ($($lv.gitSha))"
}
Write-Host "================================================================" -ForegroundColor Blue
Write-Host ""

$testCount = 0
$passCount = 0
$warnCount = 0
$failCount = 0

function Record-Result {
    param([bool]$Pass, [bool]$IsWarn = $false)
    $script:testCount++
    if ($Pass) { $script:passCount++ }
    elseif ($IsWarn) { $script:warnCount++ }
    else { $script:failCount++ }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 1: Prerequisites (Full only)
# ═══════════════════════════════════════════════════════════════════════════════
if ($Full) {
    Write-Diag "Prerequisites" "HEAD"

    $tools = @("docker", "node", "python", "git", "npm")
    foreach ($tool in $tools) {
        if (Test-Command $tool) {
            $ver = & $tool --version 2>&1 | Select-Object -First 1
            Write-Diag "$tool : $ver" "OK"
            Record-Result $true
        } else {
            Write-Diag "$tool is not installed" "FAIL"
            Record-Result $false
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 2: Docker status
# ═══════════════════════════════════════════════════════════════════════════════
if ($Full -or $Quick) {
    Write-Diag "Docker" "HEAD"

    $dockerRunning = $false
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Diag "Docker daemon is running" "OK"
        Record-Result $true
        $dockerRunning = $true
    } else {
        Write-Diag "Docker daemon is NOT running" "FAIL"
        Record-Result $false
    }

    if ($dockerRunning) {
        # List containers
        Write-Diag "Containers" "HEAD"
        $containers = docker ps --format "{{.Names}}" 2>$null
        $expectedContainers = @("auth-service", "accounting-service", "flowise-proxy", "bridge", "flowise", "mongodb")

        foreach ($name in $expectedContainers) {
            $found = $containers | Where-Object { $_ -like "*$name*" }
            if ($found) {
                $status = docker inspect --format '{{.State.Status}}' $found 2>$null
                Write-Diag "$name : $status" "OK"
                Record-Result $true
            } else {
                Write-Diag "$name container not found" "WARN"
                Record-Result $false $true
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 3: Service health endpoints
# ═══════════════════════════════════════════════════════════════════════════════
if ($Full -or $Quick) {
    Write-Diag "Health Endpoints" "HEAD"

    $endpoints = @(
        @{ Name = "Auth API";    Url = "http://localhost:3000/health" },
        @{ Name = "Accounting";  Url = "http://localhost:3001/health" },
        @{ Name = "Proxy API";   Url = "http://localhost:8000/health" },
        @{ Name = "Bridge UI";   Url = "http://localhost:3082/" },
        @{ Name = "Flowise";     Url = "http://localhost:3002/" }
    )

    foreach ($ep in $endpoints) {
        try {
            $r = Invoke-WebRequest -Uri $ep.Url -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($r.StatusCode -eq 200) {
                Write-Diag "$($ep.Name) ($($ep.Url)) -- HTTP 200" "OK"
                Record-Result $true
            } else {
                Write-Diag "$($ep.Name) -- HTTP $($r.StatusCode)" "WARN"
                Record-Result $false $true
            }
        } catch {
            Write-Diag "$($ep.Name) -- not responding" "FAIL"
            Record-Result $false
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 4: Port availability
# ═══════════════════════════════════════════════════════════════════════════════
if ($Full) {
    Write-Diag "Ports" "HEAD"

    $ports = @(3000, 3001, 3002, 3082, 8000, 27017)
    foreach ($port in $ports) {
        $listener = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($listener) {
            $proc = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
            Write-Diag "Port $port : in use by $($proc.ProcessName) (PID $($listener.OwningProcess))" "OK"
            Record-Result $true
        } else {
            Write-Diag "Port $port : not in use" "WARN"
            Record-Result $false $true
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 5: .env files
# ═══════════════════════════════════════════════════════════════════════════════
if ($Full) {
    Write-Diag ".env Files" "HEAD"

    $services = @("auth-service", "accounting-service", "flowise-proxy-service-py", "bridge", "flowise")
    foreach ($svc in $services) {
        $envFile = Join-Path $scriptRoot "$svc\.env"
        if (Test-Path $envFile) {
            Write-Diag "$svc/.env exists" "OK"
            Record-Result $true
        } else {
            Write-Diag "$svc/.env MISSING" "FAIL"
            Record-Result $false
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 6: JWT secret sync check
# ═══════════════════════════════════════════════════════════════════════════════
if ($Full -or $Login) {
    Write-Diag "JWT Secret Synchronisation" "HEAD"

    $jwtSecrets = @()
    $jwtFiles = @("auth-service\.env", "accounting-service\.env", "flowise-proxy-service-py\.env")
    foreach ($f in $jwtFiles) {
        $envPath = Join-Path $scriptRoot $f
        if (Test-Path $envPath) {
            $content = Get-Content $envPath -Raw
            if ($content -match 'JWT_SECRET=(\S+)') {
                $jwtSecrets += $Matches[1]
            }
        }
    }

    $uniqueSecrets = $jwtSecrets | Select-Object -Unique
    if ($uniqueSecrets.Count -eq 1 -and $jwtSecrets.Count -eq 3) {
        Write-Diag "All 3 services share the same JWT_SECRET" "OK"
        Record-Result $true
    } elseif ($jwtSecrets.Count -eq 0) {
        Write-Diag "No JWT_SECRET found in any .env file" "FAIL"
        Record-Result $false
    } else {
        Write-Diag "JWT_SECRET mismatch across services! Found $($uniqueSecrets.Count) unique values." "FAIL"
        Record-Result $false
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 7: Login diagnostics
# ═══════════════════════════════════════════════════════════════════════════════
if ($Login) {
    Write-Diag "Login Diagnostics" "HEAD"

    # Check auth service
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:3000/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        Write-Diag "Auth service responding" "OK"
        Record-Result $true
    } catch {
        Write-Diag "Auth service not responding -- login will fail" "FAIL"
        Record-Result $false
    }

    # Check CORS config
    $authEnv = Join-Path $scriptRoot "auth-service\.env"
    if (Test-Path $authEnv) {
        $content = Get-Content $authEnv -Raw
        if ($content -match 'CORS_ORIGIN') {
            Write-Diag "CORS_ORIGIN is configured in auth-service" "OK"
            Record-Result $true
        } else {
            Write-Diag "CORS_ORIGIN not set -- may cause browser login issues" "WARN"
            Record-Result $false $true
        }
    }

    # Check MongoDB container
    $mongoContainer = docker ps --filter "name=mongo" --format "{{.Names}}" 2>$null | Select-Object -First 1
    if ($mongoContainer) {
        Write-Diag "MongoDB container running: $mongoContainer" "OK"
        Record-Result $true

        # Check if auth_db exists
        $dbCheck = docker exec $mongoContainer mongosh --quiet --eval "db.adminCommand('listDatabases').databases.map(d => d.name)" 2>$null
        if ($dbCheck -match "auth_db") {
            Write-Diag "auth_db database exists" "OK"
            Record-Result $true
        } else {
            Write-Diag "auth_db database not found" "FAIL"
            Record-Result $false
        }
    } else {
        Write-Diag "MongoDB container not running" "FAIL"
        Record-Result $false
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 8: User list
# ═══════════════════════════════════════════════════════════════════════════════
if ($Users) {
    Write-Diag "User List" "HEAD"

    $mongoContainer = docker ps --filter "name=mongo" --format "{{.Names}}" 2>$null | Select-Object -First 1
    if ($mongoContainer) {
        $userQuery = 'db.getSiblingDB("auth_db").users.find({},{username:1,email:1,role:1,isVerified:1,_id:0}).toArray()'
        $result = docker exec $mongoContainer mongosh --quiet --eval $userQuery 2>$null
        if ($result) {
            Write-Host ""
            Write-Host "  Users in auth_db:" -ForegroundColor White
            $result | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Host ""
        } else {
            Write-Diag "No users found or query failed" "WARN"
        }
    } else {
        Write-Diag "MongoDB not running -- cannot list users" "FAIL"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  Diagnostic Summary" -ForegroundColor Blue
Write-Host "================================================================" -ForegroundColor Blue
Write-Host "  Tests: $testCount  |  Pass: $passCount  |  Warn: $warnCount  |  Fail: $failCount" -ForegroundColor $(
    if ($failCount -gt 0) { "Red" } elseif ($warnCount -gt 0) { "Yellow" } else { "Green" }
)
Write-Host "================================================================" -ForegroundColor Blue

if ($SaveLog -or $Full) {
    $logPath = Join-Path $scriptRoot "logs\diagnose_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $logsDir = Split-Path $logPath -Parent
    if (-not (Test-Path $logsDir)) { New-Item -Path $logsDir -ItemType Directory -Force | Out-Null }
    $logLines | Set-Content $logPath
    Write-Host "  Log saved: $logPath" -ForegroundColor DarkGray
}
Write-Host ""
