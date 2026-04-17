<#
.SYNOPSIS
    Creates a local 'fleet' admin account for SSH access.
    Run as Administrator on the workstation.
#>

$ErrorActionPreference = 'Stop'

$Username = "fleet"
$Password = "FleetSSH-2026!"

Write-Host "=== Create Fleet SSH User ===" -ForegroundColor Cyan

# ── 1. Create local user ─────────────────────────────────────────
Write-Host "`n[1/4] Creating local user '$Username'..."
$existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "  User already exists." -ForegroundColor Green
} else {
    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -Password $secPass -Description "Fleet management SSH access" -PasswordNeverExpires -AccountNeverExpires
    Write-Host "  User created." -ForegroundColor Green
}

# ── 2. Add to Administrators group ──────────────────────────────
Write-Host "`n[2/4] Adding to Administrators group..."
$members = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
if ($members -match "\\$Username$") {
    Write-Host "  Already in Administrators." -ForegroundColor Green
} else {
    Add-LocalGroupMember -Group "Administrators" -Member $Username
    Write-Host "  Added to Administrators." -ForegroundColor Green
}

# ── 3. Create user profile ──────────────────────────────────────
Write-Host "`n[3/4] Creating user profile..."
$profilePath = "C:\Users\$Username"
if (Test-Path $profilePath) {
    Write-Host "  Profile already exists at $profilePath" -ForegroundColor Green
} else {
    # Trigger profile creation by running a process as the user
    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($Username, $secPass)
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "echo profile created" -Credential $cred -Wait -NoNewWindow -ErrorAction SilentlyContinue
    if (Test-Path $profilePath) {
        Write-Host "  Profile created at $profilePath" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Profile may not have been created. It will be created on first SSH login." -ForegroundColor Yellow
    }
}

# ── 4. Verify administrators_authorized_keys ─────────────────────
Write-Host "`n[4/4] Verifying SSH key setup..."
$adminKeysFile = "C:\ProgramData\ssh\administrators_authorized_keys"
$expectedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHyHCqZE1yaZK0pWO7SP2n7ZvJ0KR3n5MUiB+KThPHaN fleet-management"

if (Test-Path $adminKeysFile) {
    $content = Get-Content $adminKeysFile -Raw
    if ($content -and $content.Contains($expectedKey)) {
        Write-Host "  Fleet SSH key present in $adminKeysFile" -ForegroundColor Green
    } else {
        Add-Content -Path $adminKeysFile -Value $expectedKey
        Write-Host "  Fleet SSH key added to $adminKeysFile" -ForegroundColor Green
    }
} else {
    Set-Content -Path $adminKeysFile -Value $expectedKey
    # Fix ACLs
    $acl = Get-Acl $adminKeysFile
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","Allow")))
    Set-Acl -Path $adminKeysFile -AclObject $acl
    Write-Host "  Created $adminKeysFile with fleet key and correct ACLs" -ForegroundColor Green
}

# Restart sshd to pick up any changes
Restart-Service sshd

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "SSH user: $Username" -ForegroundColor Cyan
Write-Host "Test with: ssh -i ~/.ssh/fleet_ed25519 $Username@10.10.0.2" -ForegroundColor Cyan
Write-Host "`nIMPORTANT: Change the password after setup or disable password login in sshd_config" -ForegroundColor Yellow
