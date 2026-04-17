<#
.SYNOPSIS
    Set up WireGuard on a Windows workstation to join the fleet VPN.

.DESCRIPTION
    Installs WireGuard (if not present), generates a key pair, and creates
    the tunnel configuration to connect to the AWS hub.

    After running this script:
    1. Copy the printed public key
    2. Add it to fleet-inventory.json peers
    3. Run terraform apply to update the hub
    4. Activate the tunnel: wireguard /installtunnelservice wg-fleet

.PARAMETER HubEndpoint
    Public IP:port of the WireGuard hub (Elastic IP from Terraform output)

.PARAMETER HubPublicKey
    WireGuard public key of the hub (retrieve via SSM or Terraform output)

.PARAMETER MyIP
    This workstation's VPN IP, e.g. "10.10.0.2/24"

.PARAMETER TunnelName
    Name for the WireGuard tunnel (default: wg-fleet)

.EXAMPLE
    .\wg-workstation-setup.ps1 -HubEndpoint "3.5.7.9:51820" -HubPublicKey "abc123=" -MyIP "10.10.0.2/24"
#>

param(
    [Parameter(Mandatory)]
    [string]$HubEndpoint,

    [Parameter(Mandatory)]
    [string]$HubPublicKey,

    [Parameter(Mandatory)]
    [string]$MyIP,

    [string]$TunnelName = 'wg-fleet'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Step ($msg) { Write-Host "`n── $msg ──" -ForegroundColor Cyan }

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host " WireGuard Workstation Setup" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan

# ── Step 1: Check/Install WireGuard ─────────────────────────────────

Write-Step "Step 1: Check WireGuard installation"

$wgExe = Get-Command wireguard -ErrorAction SilentlyContinue
if (-not $wgExe) {
    $wgExe = Get-Command 'C:\Program Files\WireGuard\wireguard.exe' -ErrorAction SilentlyContinue
}

if (-not $wgExe) {
    Write-Host "  WireGuard not found. Install from: https://www.wireguard.com/install/" -ForegroundColor Yellow
    Write-Host "  Or run: winget install WireGuard.WireGuard" -ForegroundColor Yellow

    $install = Read-Host "  Install with winget now? (y/n)"
    if ($install -eq 'y') {
        winget install WireGuard.WireGuard --accept-package-agreements --accept-source-agreements
        # Refresh PATH
        $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    }
    else {
        Write-Fail "WireGuard required. Aborting."
        exit 1
    }
}
Write-OK "WireGuard installed"

# ── Step 2: Generate key pair ────────────────────────────────────────

Write-Step "Step 2: Generate WireGuard keys"

$wgDir = "$env:USERPROFILE\.wireguard"
if (-not (Test-Path $wgDir)) { New-Item -ItemType Directory -Path $wgDir -Force | Out-Null }

$privKeyFile = "$wgDir\private.key"
$pubKeyFile  = "$wgDir\public.key"

if (Test-Path $privKeyFile) {
    Write-Host "  Existing keys found, reusing."
    $privKey = Get-Content $privKeyFile -Raw
    $pubKey  = Get-Content $pubKeyFile -Raw
}
else {
    # Use wg.exe to generate keys
    $wgTool = 'C:\Program Files\WireGuard\wg.exe'
    if (-not (Test-Path $wgTool)) {
        Write-Fail "wg.exe not found at $wgTool"
        exit 1
    }

    $privKey = & $wgTool genkey
    $pubKey  = $privKey | & $wgTool pubkey

    Set-Content -Path $privKeyFile -Value $privKey -NoNewline
    Set-Content -Path $pubKeyFile -Value $pubKey -NoNewline

    # Restrict permissions on private key
    $acl = Get-Acl $privKeyFile
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $privKeyFile -AclObject $acl
}

Write-OK "Keys ready"

# ── Step 3: Create tunnel config ────────────────────────────────────

Write-Step "Step 3: Create tunnel configuration"

$configDir = 'C:\Program Files\WireGuard\Data\Configurations'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$configPath = "$configDir\$TunnelName.conf"

$config = @"
[Interface]
PrivateKey = $($privKey.Trim())
Address = $MyIP
DNS = 1.1.1.1

[Peer]
PublicKey = $($HubPublicKey.Trim())
Endpoint = $HubEndpoint
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
"@

Set-Content -Path $configPath -Value $config -Force
Write-OK "Config written to $configPath"

# ── Step 4: Enable OpenSSH ──────────────────────────────────────────

Write-Step "Step 4: Ensure OpenSSH server is running"

$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $sshd) {
    Write-Host "  Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    $sshd = Get-Service sshd -ErrorAction SilentlyContinue
}

if ($sshd.Status -ne 'Running') {
    Set-Service sshd -StartupType Automatic
    Start-Service sshd
}
Write-OK "OpenSSH server running"

# ── Summary ─────────────────────────────────────────────────────────

Write-Step "Setup Complete"
Write-Host ""
Write-Host "  Your WireGuard public key:" -ForegroundColor Yellow
Write-Host "  $($pubKey.Trim())" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Add this public key to infra/modules/wireguard peers variable"
Write-Host "  2. Run: terraform apply (to update hub config)"
Write-Host "  3. Activate tunnel:" -ForegroundColor Cyan
Write-Host "     wireguard /installtunnelservice `"$configPath`"" -ForegroundColor White
Write-Host "  4. Verify: ping 10.10.0.1" -ForegroundColor Cyan
Write-Host ""
