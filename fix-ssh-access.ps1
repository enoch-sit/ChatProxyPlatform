#!/usr/bin/env pwsh
<#
.SYNOPSIS
    fix-ssh-access.ps1 - Fix SSH connectivity issues (firewall, authorized_keys, config)
    
.DESCRIPTION
    Applies all necessary fixes to enable SSH remote access:
    1. Creates firewall rule for SSH port 22
    2. Creates fleet user SSH directory and authorized_keys
    3. Uncomments ListenAddress in sshd_config
    4. Restarts SSH service
    
.PARAMETER ManagementPublicKey
    The public key from management machine (~/.ssh/fleet_ed25519.pub)
    If not provided, will prompt for it
    
.EXAMPLE
    .\fix-ssh-access.ps1
    
    .\fix-ssh-access.ps1 -ManagementPublicKey "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..."
    
.NOTES
    Requires Administrator privileges
    Will restart the SSH service
#>

param(
    [string]$ManagementPublicKey
)

$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# Check admin privileges
# ──────────────────────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "  SSH ACCESS FIX" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Create firewall rule for SSH
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "`n[1/5] Creating firewall rule for SSH..." -ForegroundColor Yellow

$existingRule = Get-NetFirewallRule -Name "SSH" -ErrorAction SilentlyContinue
if ($existingRule) {
    Write-Host "  Firewall rule 'SSH' already exists, skipping..."
} else {
    New-NetFirewallRule -Name "SSH" `
        -DisplayName "SSH Server (sshd)" `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 22 `
        -Action Allow `
        -ErrorAction Stop | Out-Null
    Write-Host "  [OK] Created firewall rule for SSH port 22" -ForegroundColor Green
}

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Get management public key
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "`n[2/5] Setting up authorized_keys..." -ForegroundColor Yellow

if (-not $ManagementPublicKey) {
    Write-Host "  Enter the public key from management machine (~/.ssh/fleet_ed25519.pub):" -ForegroundColor Cyan
    Write-Host "  (Paste the entire ssh-ed25519 AAAA... line)" -ForegroundColor Gray
    $ManagementPublicKey = Read-Host "  Public Key"
    Write-Host ""
}

# Validate public key format
if (-not ($ManagementPublicKey -match "ssh-ed25519|ssh-rsa|ecdsa-sha2")) {
    Write-Host "  ERROR: Invalid public key format" -ForegroundColor Red
    Write-Host "  Should start with: ssh-ed25519, ssh-rsa, or ecdsa-sha2" -ForegroundColor Yellow
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Create fleet user SSH directory and authorized_keys
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "  Creating fleet user SSH directory..." -ForegroundColor Cyan

$fleetUserPath = "C:\Users\fleet"
$fleetSshPath = "$fleetUserPath\.ssh"

if (-not (Test-Path $fleetSshPath)) {
    New-Item -ItemType Directory -Path $fleetSshPath -Force | Out-Null
    Write-Host "    Created: $fleetSshPath" -ForegroundColor Green
}

$authorizedKeysPath = "$fleetSshPath\authorized_keys"
if (Test-Path $authorizedKeysPath) {
    Write-Host "    Authorized_keys already exists, checking for key..." -ForegroundColor Cyan
    $existingKeys = Get-Content $authorizedKeysPath
    if ($existingKeys -contains $ManagementPublicKey) {
        Write-Host "    [OK] Management key already in authorized_keys" -ForegroundColor Green
    } else {
        Add-Content -Path $authorizedKeysPath -Value "`n$ManagementPublicKey"
        Write-Host "    [OK] Added management key to authorized_keys" -ForegroundColor Green
    }
} else {
    Set-Content -Path $authorizedKeysPath -Value $ManagementPublicKey
    Write-Host "    [OK] Created authorized_keys with management public key" -ForegroundColor Green
}

# Set correct permissions on .ssh directory and authorized_keys
icacls $fleetSshPath /inheritance:r /grant:r "fleet:(OI)(CI)F" | Out-Null
icacls $authorizedKeysPath /inheritance:r /grant:r "fleet:(OI)(CI)F" | Out-Null
Write-Host "    [OK] Set correct permissions on .ssh and authorized_keys" -ForegroundColor Green

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Uncomment ListenAddress in sshd_config
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "`n[3/5] Updating SSH configuration..." -ForegroundColor Yellow

$sshConfigPath = "C:\ProgramData\ssh\sshd_config"
$configContent = Get-Content $sshConfigPath

# Check if already uncommented
if ($configContent -match "^ListenAddress 0.0.0.0") {
    Write-Host "  ListenAddress 0.0.0.0 already uncommented" -ForegroundColor Green
} else {
    # Uncomment ListenAddress 0.0.0.0 and ListenAddress ::
    $configContent = $configContent -replace "^#ListenAddress 0.0.0.0", "ListenAddress 0.0.0.0"
    $configContent = $configContent -replace "^#ListenAddress ::", "ListenAddress ::"
    Set-Content -Path $sshConfigPath -Value $configContent
    Write-Host "  [OK] Uncommented ListenAddress directives" -ForegroundColor Green
}

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: Restart SSH service
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "`n[4/5] Restarting SSH service..." -ForegroundColor Yellow

Restart-Service -Name sshd -Force -ErrorAction Stop
Write-Host "  [OK] SSH service restarted" -ForegroundColor Green

# Wait for service to be ready
Start-Sleep -Seconds 2

# ──────────────────────────────────────────────────────────────────────────────
# Step 6: Verify
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "`n[5/5] Verifying SSH is ready..." -ForegroundColor Yellow

$sshService = Get-Service sshd
$sshListening = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue

Write-Host "  SSH Service Status: $($sshService.Status)" -ForegroundColor Green
Write-Host "  Listening ports: $(($sshListening | Measure-Object).Count) connections" -ForegroundColor Green
Write-Host "  Firewall rule SSH: $(if ($existingRule -or (Get-NetFirewallRule -Name 'SSH' -ErrorAction SilentlyContinue)) { 'Enabled' } else { 'Not found' })" -ForegroundColor Green
Write-Host "  Authorized keys: $(if (Test-Path $authorizedKeysPath) { 'Present' } else { 'Not found' })" -ForegroundColor Green

Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host "  FIX COMPLETE" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan

Write-Host "`nFrom management machine, test SSH connection:" -ForegroundColor Cyan
Write-Host "  ssh -i ~/.ssh/fleet_ed25519 fleet@10.10.0.2 'echo SSH OK'`n" -ForegroundColor Yellow

Write-Host "If you get 'SSH OK', you're ready to deploy!`n" -ForegroundColor Green
