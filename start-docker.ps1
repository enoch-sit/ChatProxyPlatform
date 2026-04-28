#!/usr/bin/env pwsh
<#
.SYNOPSIS
    start-docker.ps1 - Start Docker Desktop and wait for it to be ready
    
.DESCRIPTION
    Starts Docker Desktop service and waits for the daemon to be responsive.
    Useful for automated deployment workflows.
    
.EXAMPLE
    .\start-docker.ps1
    
.NOTES
    Requires Windows 11 Pro/Enterprise with Docker Desktop installed
#>

param(
    [int]$TimeoutSeconds = 120,
    [int]$RetryIntervalSeconds = 5
)

$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$msg, [string]$color = "Cyan")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor $color
}

Write-Status "Starting Docker Desktop..." "Yellow"

try {
    # Check if Docker is already running
    $dockerCheck = docker ps 2>&1
    if ($dockerCheck -and -not ($dockerCheck -like "*Cannot connect*")) {
        Write-Status "Docker is already running!" "Green"
        exit 0
    }
} catch {
    # Docker not responding, continue with startup
}

# Start Docker Desktop
$dockerPath = "C:\Program Files\Docker\Docker\Docker.exe"
if (-not (Test-Path $dockerPath)) {
    Write-Status "ERROR: Docker Desktop not found at $dockerPath" "Red"
    exit 1
}

Write-Status "Launching Docker.exe..." "Yellow"
Start-Process $dockerPath -ErrorAction SilentlyContinue

# Wait for Docker daemon to be responsive
$elapsed = 0
$ready = $false

while ($elapsed -lt $TimeoutSeconds) {
    try {
        $result = & docker ps 2>&1
        if ($result -and -not ($result -like "*Cannot connect*" -or $result -like "*error*")) {
            Write-Status "✓ Docker daemon is responsive!" "Green"
            $ready = $true
            break
        }
    } catch {
        # Still not ready
    }
    
    Write-Status "Waiting for Docker daemon... ($elapsed/$TimeoutSeconds seconds)" "Cyan"
    Start-Sleep -Seconds $RetryIntervalSeconds
    $elapsed += $RetryIntervalSeconds
}

if ($ready) {
    Write-Status "Docker Desktop is ready. Showing running containers:" "Green"
    docker ps
    exit 0
} else {
    Write-Status "ERROR: Docker did not become responsive within $TimeoutSeconds seconds" "Red"
    exit 1
}
