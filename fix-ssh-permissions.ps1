#!/usr/bin/env pwsh
<#
.SYNOPSIS
    fix-ssh-permissions.ps1 - Fix SSH directory and file permissions
    
.DESCRIPTION
    Ensures fleet user can access .ssh and authorized_keys files
    
.EXAMPLE
    .\fix-ssh-permissions.ps1
    
.NOTES
    Requires Administrator privileges
#>

$ErrorActionPreference = "Stop"

# Check admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges" -ForegroundColor Red
    exit 1
}

Write-Host "`nFixing SSH directory permissions..." -ForegroundColor Yellow

$fleetUserPath = "C:\Users\fleet"
$fleetSshPath = "$fleetUserPath\.ssh"
$authorizedKeysPath = "$fleetSshPath\authorized_keys"

# Get fleet user SID
$fleetUser = Get-LocalUser -Name "fleet" -ErrorAction SilentlyContinue
if (-not $fleetUser) {
    Write-Host "ERROR: Fleet user not found" -ForegroundColor Red
    exit 1
}

# Remove all existing ACLs and set new ones
Write-Host "Setting permissions on $fleetSshPath..."
& icacls $fleetSshPath /inheritance:r /grant:r "$($fleetUser.Name):(OI)(CI)F" | Out-Null
Write-Host "  [OK] Permissions set on .ssh directory" -ForegroundColor Green

Write-Host "Setting permissions on $authorizedKeysPath..."
& icacls $authorizedKeysPath /inheritance:r /grant:r "$($fleetUser.Name):(OI)(CI)F" | Out-Null
Write-Host "  [OK] Permissions set on authorized_keys" -ForegroundColor Green

# Verify
Write-Host "`nVerifying permissions..."
& icacls $fleetSshPath
Write-Host ""
& icacls $authorizedKeysPath

Write-Host "`nTest SSH from management machine:" -ForegroundColor Cyan
Write-Host "  ssh -i ~/.ssh/fleet_ed25519 fleet@10.10.0.2 'echo SSH OK'`n" -ForegroundColor Yellow
