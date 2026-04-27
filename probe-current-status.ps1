#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Prints a concise status snapshot for the current ChatProxy machine.

.DESCRIPTION
    Read-only probe for workstation state. Intended for operators who want a
    quick status view before or after patching without running the stricter
    patch safety probe.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\probe-current-status.ps1
#>

$ErrorActionPreference = "Continue"

function Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Show-StatusLine {
    param(
        [ValidateSet("OK", "WARN", "FAIL", "INFO")]
        [string]$Level,
        [string]$Message
    )

    $color = switch ($Level) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }

    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $color
}

function Get-RepoRoot {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }

    return (Get-Location).Path
}

function Test-HttpStatus {
    param(
        [string]$Url,
        [int]$TimeoutSec = 4
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        return [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }

        return 0
    }
}

function Test-PortListening {
    param([int]$Port)

    try {
        $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop | Select-Object -First 1
        return $null -ne $listener
    }
    catch {
        return $false
    }
}

$repoRoot = Get-RepoRoot
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Section "Machine Status Snapshot"
Show-StatusLine INFO "Time: $timestamp"
Show-StatusLine INFO "Machine: $env:COMPUTERNAME"
Show-StatusLine INFO "User: $env:USERNAME"
Show-StatusLine INFO "Repo: $repoRoot"

Section "Git"
try {
    $branch = git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null
    $shortHead = git -C $repoRoot rev-parse --short HEAD 2>$null
    $statusLines = @(git -C $repoRoot status --short --branch 2>$null)

    if ($branch) {
        Show-StatusLine OK "Branch: $branch"
        Show-StatusLine INFO "Commit: $shortHead"
        foreach ($line in $statusLines) {
            Write-Host "  $line" -ForegroundColor Gray
        }
    }
    else {
        Show-StatusLine FAIL "Git state unavailable"
    }
}
catch {
    Show-StatusLine FAIL "Git probe failed: $($_.Exception.Message)"
}

Section "Docker"
try {
    $dockerVersion = docker version --format "{{.Server.Version}}" 2>$null
    if ($dockerVersion) {
        Show-StatusLine OK "Docker server version: $dockerVersion"
        $dockerRows = @(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>$null)
        foreach ($row in $dockerRows) {
            Write-Host "  $row" -ForegroundColor Gray
        }
    }
    else {
        Show-StatusLine FAIL "Docker is not responding"
    }
}
catch {
    Show-StatusLine FAIL "Docker probe failed: $($_.Exception.Message)"
}

Section "Service Containers"
$containers = @(
    @{ Label = "auth-service"; Name = "auth-service" },
    @{ Label = "accounting-service"; Name = "accounting-service" },
    @{ Label = "flowise-proxy"; Name = "flowise-proxy" },
    @{ Label = "bridge-ui"; Name = "bridge-ui" },
    @{ Label = "flowise"; Name = "flowise" },
    @{ Label = "flowise-postgres"; Name = "flowise-postgres" }
)

foreach ($container in $containers) {
    try {
        $state = docker inspect $container.Name --format "{{.State.Status}}" 2>$null
        if (-not $state) {
            Show-StatusLine WARN "$($container.Label): not found"
            continue
        }

        if ($state -eq "running") {
            Show-StatusLine OK "$($container.Label): running"
        }
        else {
            Show-StatusLine WARN "$($container.Label): $state"
        }
    }
    catch {
        Show-StatusLine WARN "$($container.Label): inspect failed"
    }
}

Section "Ports"
$ports = @(
    @{ Label = "auth-service"; Port = 3000 },
    @{ Label = "accounting-service"; Port = 3001 },
    @{ Label = "flowise-proxy"; Port = 8000 },
    @{ Label = "bridge-ui"; Port = 3082 },
    @{ Label = "flowise"; Port = 3002 }
)

foreach ($entry in $ports) {
    if (Test-PortListening -Port $entry.Port) {
        Show-StatusLine OK "$($entry.Label) listening on $($entry.Port)"
    }
    else {
        Show-StatusLine WARN "$($entry.Label) not listening on $($entry.Port)"
    }
}

Section "HTTP Health"
$checks = @(
    @{ Label = "auth-service"; Url = "http://localhost:3000/health" },
    @{ Label = "accounting-service"; Url = "http://localhost:3001/health" },
    @{ Label = "flowise-proxy"; Url = "http://localhost:8000/health" },
    @{ Label = "bridge-ui"; Url = "http://localhost:3082/" },
    @{ Label = "flowise"; Url = "http://localhost:3002/api/v1/ping" }
)

foreach ($check in $checks) {
    $statusCode = Test-HttpStatus -Url $check.Url
    if ($statusCode -eq 200) {
        Show-StatusLine OK "$($check.Label): HTTP 200"
    }
    elseif ($statusCode -gt 0) {
        Show-StatusLine WARN "$($check.Label): HTTP $statusCode"
    }
    else {
        Show-StatusLine WARN "$($check.Label): unreachable"
    }
}

Section "System"
try {
    $systemDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    if ($systemDrive) {
        $freeGb = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $sizeGb = [math]::Round($systemDrive.Size / 1GB, 2)
        Show-StatusLine INFO "Disk C: $freeGb GB free of $sizeGb GB"
    }
}
catch {
    Show-StatusLine WARN "Could not read disk usage"
}

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $bootTime = $os.LastBootUpTime
    Show-StatusLine INFO "Last boot: $bootTime"
}
catch {
    Show-StatusLine WARN "Could not read last boot time"
}

Section "Quick Commands"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose-bhss-state.ps1" -ForegroundColor Gray
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\diagnose.ps1" -ForegroundColor Gray
Write-Host "  python .\local-deploy.py --status" -ForegroundColor Gray