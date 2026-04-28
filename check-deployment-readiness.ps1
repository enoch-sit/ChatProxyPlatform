#!/usr/bin/env pwsh
<#
.SYNOPSIS
    check-deployment-readiness.ps1 - Verify workstation is ready for deployment
    
.DESCRIPTION
    Checks all prerequisites for deployment:
    - SSH service running
    - Docker daemon responsive
    - WireGuard VPN active
    - Git repo ready
    - Services configured
    
.EXAMPLE
    .\check-deployment-readiness.ps1
    
.NOTES
    Run this before attempting fleet.ps1 -Action patch
#>

$ErrorActionPreference = "Continue"

function Write-Check {
    param([string]$name, [bool]$status, [string]$details = "")
    $symbol = if ($status) { "[✓]" } else { "[✗]" }
    $color = if ($status) { "Green" } else { "Red" }
    Write-Host "$symbol $name" -ForegroundColor $color
    if ($details) { Write-Host "   $details" -ForegroundColor Gray }
}

Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "  DEPLOYMENT READINESS CHECK" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

$allGood = $true

# Check SSH
Write-Host "`n--- SSH Service ---" -ForegroundColor Yellow
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
$sshRunning = $sshService -and $sshService.Status -eq "Running"
Write-Check "SSH Service Running" $sshRunning ($sshService.Status)
$allGood = $allGood -and $sshRunning

# Check SSH Port Listening
$sshListening = Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Listen" }
Write-Check "SSH Port 22 Listening" ($null -ne $sshListening) "$(($sshListening | Measure-Object).Count) connections"
$allGood = $allGood -and ($null -ne $sshListening)

# Check Docker
Write-Host "`n--- Docker ---" -ForegroundColor Yellow
try {
    $dockerVersion = & docker version 2>&1 | Select-Object -First 1
    $dockerRunning = $dockerVersion -and -not ($dockerVersion -like "*Cannot connect*")
    Write-Check "Docker Running" $dockerRunning $dockerVersion
    $allGood = $allGood -and $dockerRunning
    
    if ($dockerRunning) {
        $containers = & docker ps -q 2>$null | Measure-Object
        Write-Check "Docker Containers" ($containers.Count -gt 0) "$($containers.Count) running"
    }
} catch {
    Write-Check "Docker Running" $false $_.Exception.Message
    $allGood = $false
}

# Check WireGuard
Write-Host "`n--- WireGuard VPN ---" -ForegroundColor Yellow
$wgInterface = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -eq "wg-fleet" }
$wgActive = $wgInterface -and $wgInterface.IPv4Address.IPAddress -eq "10.10.0.2"
Write-Check "WireGuard Active" $wgActive "IP: $($wgInterface.IPv4Address.IPAddress)"
$allGood = $allGood -and $wgActive

# Check Git
Write-Host "`n--- Git Repository ---" -ForegroundColor Yellow
$gitBranch = & git branch --show-current 2>$null
$gitCorrect = $gitBranch -eq "deploy/localdeploy"
Write-Check "Git Branch Correct" $gitCorrect "Branch: $gitBranch"
$allGood = $allGood -and $gitCorrect

# Check Environment Files
Write-Host "`n--- Environment Configuration ---" -ForegroundColor Yellow
$envFiles = @(
    "auth-service\.env",
    "accounting-service\.env",
    "bridge\.env",
    "flowise\.env",
    "flowise-proxy-service-py\.env"
)
$envMissing = @()
foreach ($env in $envFiles) {
    $exists = Test-Path $env
    if (-not $exists) { $envMissing += $env }
    Write-Check $env $exists ""
}
if ($envMissing.Count -gt 0) {
    $allGood = $false
}

# Check Disk Space
Write-Host "`n--- Disk Space ---" -ForegroundColor Yellow
$volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.SizeRemaining -gt 0 }
foreach ($vol in $volumes) {
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
    $totalGB = [math]::Round($vol.Size / 1GB, 1)
    $percentFree = [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 1)
    Write-Check "Drive $($vol.DriveLetter):" ($percentFree -gt 10) "$freeGB / $totalGB GB ($percentFree% free)"
}

# Summary
Write-Host "`n=========================================================" -ForegroundColor Cyan
if ($allGood) {
    Write-Host "  ✓ READY FOR DEPLOYMENT" -ForegroundColor Green
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "`nYou can now run:"
    Write-Host "  .\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode full`n"
    exit 0
} else {
    Write-Host "  ✗ NOT READY - See issues above" -ForegroundColor Red
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "`nFix the issues above before deploying.`n"
    Write-Host "Common fixes:"
    Write-Host "  - Start Docker:    .\start-docker.ps1"
    Write-Host "  - Fix .env files:  Create missing environment files"
    Write-Host "  - Check Git:       git status`n"
    exit 1
}
