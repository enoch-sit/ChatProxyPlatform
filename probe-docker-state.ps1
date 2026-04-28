#!/usr/bin/env pwsh
<#
.SYNOPSIS
    probe-docker-state.ps1 - Diagnose and start Docker Desktop on a workstation
.DESCRIPTION
    ASCII-only probe. Reports Docker Desktop process state, service state,
    npipe availability, then attempts to start Docker Desktop if not running
    and waits for the daemon to be reachable.
#>
param(
    [int]$TimeoutSeconds = 180,
    [int]$RetryIntervalSeconds = 5
)

$ErrorActionPreference = "Continue"

function Log { param([string]$m) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $m" }

Log "=== probe-docker-state ==="
Log "Host: $env:COMPUTERNAME  User: $env:USERNAME"

# 1. Process state
$desktopProc = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
$backendProc = Get-Process -Name "com.docker.backend" -ErrorAction SilentlyContinue
Log "Docker Desktop process: $(if ($desktopProc) { 'RUNNING (PID ' + $desktopProc.Id + ')' } else { 'NOT running' })"
Log "com.docker.backend  : $(if ($backendProc) { 'RUNNING (PID ' + $backendProc.Id + ')' } else { 'NOT running' })"

# 2. Service state
$svc = Get-Service -Name "com.docker.service" -ErrorAction SilentlyContinue
if ($svc) {
    Log "Service com.docker.service: $($svc.Status) (StartType=$($svc.StartType))"
    if ($svc.Status -ne 'Running') {
        Log "Attempting to start service..."
        try { Start-Service -Name $svc.Name -ErrorAction Stop; Log "Service started." }
        catch { Log "Service start failed: $($_.Exception.Message)" }
    }
} else {
    Log "Service com.docker.service NOT found"
}

# 3. Named pipe
$pipeOk = Test-Path "\\.\pipe\docker_engine"
Log "npipe \\.\pipe\docker_engine present: $pipeOk"

# 4. Locate Docker Desktop exe
$candidates = @(
    "C:\Program Files\Docker\Docker\Docker Desktop.exe",
    "C:\Program Files\Docker\Docker\Docker.exe"
)
$exe = $null
foreach ($c in $candidates) { if (Test-Path $c) { $exe = $c; break } }
Log "Docker Desktop exe: $(if ($exe) { $exe } else { 'NOT FOUND' })"

# 5. Quick docker CLI test
$cliPath = (Get-Command docker -ErrorAction SilentlyContinue).Source
Log "docker CLI: $(if ($cliPath) { $cliPath } else { 'NOT in PATH' })"

# 6. Launch Docker Desktop if not running
if (-not $desktopProc -and $exe) {
    Log "Launching Docker Desktop..."
    try {
        Start-Process -FilePath $exe -ErrorAction Stop
        Log "Launch issued."
    } catch {
        Log "Launch failed: $($_.Exception.Message)"
    }
}

# 7. Wait for daemon
Log "Waiting for daemon (timeout=$TimeoutSeconds s)..."
$elapsed = 0
$ready = $false
while ($elapsed -lt $TimeoutSeconds) {
    $out = & docker version --format "{{.Server.Version}}" 2>&1
    if ($LASTEXITCODE -eq 0 -and $out -and ($out -notmatch 'Cannot connect|error|failed')) {
        Log "Daemon responsive. Server version: $out"
        $ready = $true
        break
    }
    Start-Sleep -Seconds $RetryIntervalSeconds
    $elapsed += $RetryIntervalSeconds
    if ($elapsed % 30 -eq 0) { Log "  still waiting... ($elapsed s)" }
}

if ($ready) {
    Log "=== docker ps ==="
    docker ps
    Log "RESULT: OK"
    exit 0
} else {
    Log "RESULT: TIMEOUT - daemon not reachable within $TimeoutSeconds s"
    Log "Last docker version output: $out"
    exit 1
}
