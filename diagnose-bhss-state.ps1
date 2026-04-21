#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Comprehensive diagnostic of ChatProxy production state on BHSS.

.DESCRIPTION
    Probes all services, ports, connectivity, and logs to understand 
    current production state before any patching.

.EXAMPLE
    .\diagnose-bhss-state.ps1
#>

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Section { 
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Ok { param([string]$m) Write-Host "[OK]    $m" -ForegroundColor Green }
function Warn { param([string]$m) Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Fail { param([string]$m) Write-Host "[FAIL]  $m" -ForegroundColor Red }
function Info { param([string]$m) Write-Host "[INFO]  $m" -ForegroundColor White }

Section "BHSS Production Diagnostic"
Info "Time: $timestamp"
Info "Machine: $env:COMPUTERNAME"
Info "User: $env:USERNAME"

# ============================================================================
Section "1. Docker Status"
Info "Checking Docker daemon..."

try {
    $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
    if ($dockerVersion) {
        Ok "Docker is running (version $dockerVersion)"
    } else {
        Fail "Docker not responding"
        exit 1
    }
} catch {
    Fail "Docker not accessible: $($_.Exception.Message)"
    exit 1
}

Info ""
Info "Running containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>$null | ForEach-Object {
    if ($_ -match '^\s*$') { return }
    Write-Host "  $_"
}

# ============================================================================
Section "2. Service Container States"

$services = @("auth-service", "accounting-service", "flowise-proxy", "bridge-ui", "flowise")
$serviceStates = @{}

foreach ($service in $services) {
    $containerName = $service
    if ($service -eq "bridge-ui") { $containerName = "bridge" }
    if ($service -eq "flowise") { $containerName = "flowise" }
    
    $state = docker inspect $containerName --format "{{.State.Status}}" 2>$null
    if ($state) {
        $serviceStates[$service] = $state
        if ($state -eq "running") {
            Ok "$service : $state"
        } else {
            Fail "$service : $state"
        }
    } else {
        Warn "$service : NOT FOUND"
        $serviceStates[$service] = "not-found"
    }
}

# ============================================================================
Section "3. Port Availability"

$ports = @(
    @{Name="Auth (3000)"; Port=3000; Service="auth-service"}
    @{Name="Accounting (3001)"; Port=3001; Service="accounting-service"}
    @{Name="Flowise Proxy (8000)"; Port=8000; Service="flowise-proxy"}
    @{Name="Bridge UI (3082)"; Port=3082; Service="bridge"}
    @{Name="Flowise (3000)"; Port=3001; Service="flowise"}
)

foreach ($portInfo in $ports) {
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ConnectAsync("127.0.0.1", $portInfo.Port) | Wait-Job -Timeout 2 | Out-Null
        if ($tcpClient.Connected) {
            Ok "$($portInfo.Name) : LISTENING"
            $tcpClient.Close()
        } else {
            Fail "$($portInfo.Name) : NOT LISTENING"
        }
    } catch {
        Fail "$($portInfo.Name) : NOT LISTENING"
    }
}

# ============================================================================
Section "4. Service Health Endpoints"

$healthChecks = @(
    @{Name="Auth"; Url="http://localhost:3000/health"}
    @{Name="Accounting"; Url="http://localhost:3001/health"}
    @{Name="Flowise Proxy"; Url="http://localhost:8000/health"}
    @{Name="Bridge"; Url="http://localhost:3082/"}
)

foreach ($check in $healthChecks) {
    try {
        $response = Invoke-WebRequest -Uri $check.Url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        Ok "$($check.Name) : HTTP $($response.StatusCode)"
    } catch {
        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -gt 0) {
            Warn "$($check.Name) : HTTP $statusCode"
        } else {
            Fail "$($check.Name) : UNREACHABLE"
        }
    }
}

# ============================================================================
Section "5. Environment Configuration"

Info "Checking key environment files..."

$envFiles = @(
    "flowise-proxy-service-py\.env"
    "auth-service\.env.local"
    "accounting-service\.env.local"
)

foreach ($envFile in $envFiles) {
    $path = Join-Path (Split-Path -Parent $PSScriptRoot) $envFile
    if (Test-Path $path) {
        $content = Get-Content $path -Raw
        if ($content -match "MONGODB_URI|DATABASE_URL|API_KEY") {
            Ok "$envFile : EXISTS (configured)"
        } else {
            Warn "$envFile : EXISTS (but may lack config)"
        }
    } else {
        Fail "$envFile : MISSING"
    }
}

# ============================================================================
Section "6. Recent Container Logs (Last 30 lines each)"

foreach ($service in $services) {
    $containerName = $service
    if ($service -eq "bridge-ui") { $containerName = "bridge" }
    if ($service -eq "flowise") { $containerName = "flowise" }
    
    if ($serviceStates[$service] -and $serviceStates[$service] -ne "not-found") {
        Info ""
        Info "=== $service ==="
        docker logs $containerName --tail 30 2>&1 | ForEach-Object {
            if ($_ -match "error|failed|exception" -and $_ -notmatch "handled") {
                Write-Host "  [ERROR] $_" -ForegroundColor Red
            } else {
                Write-Host "  $_" -ForegroundColor Gray
            }
        }
    }
}

# ============================================================================
Section "7. Network Configuration"

Info "Local IP addresses:"
try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch "^127\." } |
        Select-Object -ExpandProperty IPAddress -Unique
    $ips | ForEach-Object { Write-Host "  $_" }
} catch {
    Warn "Could not retrieve IP addresses"
}

# ============================================================================
Section "8. Diagnostic Summary"

$allHealthy = $true
foreach ($service in $services) {
    if ($serviceStates[$service] -ne "running") {
        $allHealthy = $false
        break
    }
}

if ($allHealthy) {
    Ok "All services are running"
} else {
    Fail "Some services are not running or not found"
}

Info ""
Info "RECOMMENDED NEXT STEPS:"
Info "1. If flowise-proxy is down: docker-compose -f flowise-proxy-service-py/docker-compose.yml up -d"
Info "2. If auth-service is down: docker-compose -f auth-service/docker-compose.dev.yml up -d"
Info "3. If auth login fails: check MongoDB and user table state"
Info "4. Review logs above for specific errors"
Info "5. Once services are healthy, run: .\probe-bridge-target.ps1 -PreferredHost ai01.bhss.edu.hk"

Write-Host ""
Write-Host "Diagnostic complete." -ForegroundColor Cyan
exit 0
