<#
.SYNOPSIS
    Creates or updates a local fleet admin account for SSH access.

.DESCRIPTION
    This script is designed for first-time workstation onboarding. It avoids
    hardcoded credentials and can generate a random password when not provided.

.PARAMETER Username
    Local Windows account to create/manage. Default: fleet

.PARAMETER Password
    Optional plaintext password to set for the local account. If omitted, a
    cryptographically random password is generated.

.PARAMETER PublicKey
    Optional SSH public key content to add to administrators_authorized_keys.

.PARAMETER PublicKeyPath
    Optional path to a .pub file. Used when -PublicKey is not provided.

.PARAMETER PasswordOutputPath
    File path where generated password will be written once for operator use.
    Default: C:\ProgramData\ssh\fleet-bootstrap-password.txt
#>

[CmdletBinding()]
param(
    [string]$Username = "fleet",
    [string]$Password,
    [string]$PublicKey,
    [string]$PublicKeyPath,
    [string]$PasswordOutputPath = "C:\ProgramData\ssh\fleet-bootstrap-password.txt"
)

$ErrorActionPreference = 'Stop'

function New-RandomPassword {
    param([int]$Length = 24)
    Add-Type -AssemblyName System.Web
    return [System.Web.Security.Membership]::GeneratePassword($Length, 4)
}

function Write-OK   { param([string]$Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }

Write-Host "=== Create Fleet SSH User ===" -ForegroundColor Cyan

if (-not $Password) {
    $Password = New-RandomPassword
    Set-Content -Path $PasswordOutputPath -Value "fleet user password: $Password" -Force
    Write-Warn "No password provided; generated a random password and wrote it to: $PasswordOutputPath"
}

$resolvedPublicKey = $PublicKey
if (-not $resolvedPublicKey -and $PublicKeyPath) {
    if (-not (Test-Path $PublicKeyPath)) {
        throw "PublicKeyPath not found: $PublicKeyPath"
    }
    $resolvedPublicKey = (Get-Content $PublicKeyPath -Raw).Trim()
}

# 1) Create local user
Write-Host "`n[1/4] Creating local user '$Username'..."
$existing = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
if ($existing) {
    Write-OK "User already exists."
} else {
    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -Password $secPass -Description "Fleet management SSH access" -PasswordNeverExpires -AccountNeverExpires
    Write-OK "User created."
}

# 2) Ensure Administrators membership
Write-Host "`n[2/4] Adding to Administrators group..."
$members = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
if ($members -match "\\$Username$") {
    Write-OK "Already in Administrators."
} else {
    Add-LocalGroupMember -Group "Administrators" -Member $Username
    Write-OK "Added to Administrators."
}

# 3) Create user profile
Write-Host "`n[3/4] Creating user profile..."
$profilePath = "C:\Users\$Username"
if (Test-Path $profilePath) {
    Write-OK "Profile already exists at $profilePath"
} else {
    $secPass = ConvertTo-SecureString $Password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($Username, $secPass)
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "echo profile created" -Credential $cred -Wait -NoNewWindow -ErrorAction SilentlyContinue
    if (Test-Path $profilePath) {
        Write-OK "Profile created at $profilePath"
    } else {
        Write-Warn "Profile may not have been created; it will be created on first SSH login."
    }
}

# 4) Optionally update administrators_authorized_keys
Write-Host "`n[4/4] Verifying SSH key setup..."
$adminKeysFile = "C:\ProgramData\ssh\administrators_authorized_keys"
if ($resolvedPublicKey) {
    if (Test-Path $adminKeysFile) {
        $content = Get-Content $adminKeysFile -Raw
        if ($content -and $content.Contains($resolvedPublicKey)) {
            Write-OK "Fleet SSH key already present in $adminKeysFile"
        } else {
            Add-Content -Path $adminKeysFile -Value $resolvedPublicKey
            Write-OK "Fleet SSH key added to $adminKeysFile"
        }
    } else {
        Set-Content -Path $adminKeysFile -Value $resolvedPublicKey
        $acl = Get-Acl $adminKeysFile
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "FullControl", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "Allow")))
        Set-Acl -Path $adminKeysFile -AclObject $acl
        Write-OK "Created $adminKeysFile with provided key and ACLs"
    }
} else {
    Write-Warn "No public key provided. Pass -PublicKey or -PublicKeyPath to complete SSH key bootstrap."
}

Restart-Service sshd

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "SSH user: $Username" -ForegroundColor Cyan
Write-Host "Test with: ssh -i ~/.ssh/fleet_ed25519 $Username@10.10.0.2" -ForegroundColor Cyan
Write-Host "If password was generated automatically, retrieve it from: $PasswordOutputPath" -ForegroundColor Yellow
