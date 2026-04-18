<#
.SYNOPSIS
    Run this on the REMOTE workstation (via RDP) to enable SSH for fleet management.
    Must be run as Administrator.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== OpenSSH Server Setup for Fleet Management ===" -ForegroundColor Cyan

# ── 1. Install OpenSSH Server ────────────────────────────────────────
Write-Host "`n[1/5] Installing OpenSSH Server..."
$sshServer = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshServer.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $sshServer.Name
    Write-Host "  Installed." -ForegroundColor Green
} else {
    Write-Host "  Already installed." -ForegroundColor Green
}

# ── 2. Start and enable the service ──────────────────────────────────
Write-Host "`n[2/5] Starting sshd service..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
Write-Host "  sshd running and set to auto-start." -ForegroundColor Green

# ── 3. Firewall rule ────────────────────────────────────────────────
Write-Host "`n[3/5] Configuring firewall..."
$rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
        -Profile Any
    Write-Host "  Firewall rule created." -ForegroundColor Green
} else {
    Write-Host "  Firewall rule already exists." -ForegroundColor Green
}

# ── 4. Deploy fleet SSH public key ──────────────────────────────────
Write-Host "`n[4/5] Deploying fleet SSH public key..."
$pubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHyHCqZE1yaZK0pWO7SP2n7ZvJ0KR3n5MUiB+KThPHaN fleet-management"

# For admin users, Windows OpenSSH uses administrators_authorized_keys
$adminKeysFile = "C:\ProgramData\ssh\administrators_authorized_keys"
$userKeysDir   = "$env:USERPROFILE\.ssh"
$userKeysFile  = "$userKeysDir\authorized_keys"

# Deploy to both locations
if (-not (Test-Path $userKeysDir)) { New-Item -ItemType Directory -Path $userKeysDir -Force | Out-Null }

# User authorized_keys
if (Test-Path $userKeysFile) {
    $existing = Get-Content $userKeysFile -Raw -ErrorAction SilentlyContinue
    if ($existing -and $existing.Contains($pubKey)) {
        Write-Host "  Key already in $userKeysFile" -ForegroundColor Green
    } else {
        Add-Content -Path $userKeysFile -Value $pubKey
        Write-Host "  Key added to $userKeysFile" -ForegroundColor Green
    }
} else {
    Set-Content -Path $userKeysFile -Value $pubKey
    Write-Host "  Key added to $userKeysFile" -ForegroundColor Green
}

# Admin authorized_keys (required for users in Administrators group)
$sshDir = "C:\ProgramData\ssh"
if (Test-Path $sshDir) {
    if (Test-Path $adminKeysFile) {
        $existing = Get-Content $adminKeysFile -Raw -ErrorAction SilentlyContinue
        if ($existing -and $existing.Contains($pubKey)) {
            Write-Host "  Key already in $adminKeysFile" -ForegroundColor Green
        } else {
            Add-Content -Path $adminKeysFile -Value $pubKey
            Write-Host "  Key added to $adminKeysFile" -ForegroundColor Green
        }
    } else {
        Set-Content -Path $adminKeysFile -Value $pubKey
        Write-Host "  Key added to $adminKeysFile" -ForegroundColor Green
    }

    # Fix permissions on administrators_authorized_keys (must be owned by SYSTEM/Administrators only)
    $acl = Get-Acl $adminKeysFile
    $acl.SetAccessRuleProtection($true, $false)
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "FullControl", "Allow")
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")
    $acl.AddAccessRule($adminRule)
    $acl.AddAccessRule($systemRule)
    Set-Acl -Path $adminKeysFile -AclObject $acl
    Write-Host "  Permissions set on $adminKeysFile" -ForegroundColor Green
}

# ── 5. Verify ────────────────────────────────────────────────────────
Write-Host "`n[5/5] Verifying..."
$svc = Get-Service sshd
Write-Host "  sshd status: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') {'Green'} else {'Red'})
Write-Host "  SSH user: $env:USERNAME" -ForegroundColor Yellow
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Yellow

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "Fleet can now connect with: ssh -i ~/.ssh/fleet_ed25519 $env:USERNAME@10.10.0.2" -ForegroundColor Cyan
