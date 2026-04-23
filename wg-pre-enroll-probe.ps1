<#
.SYNOPSIS
    Pre-enrollment probe: assess workstation state and network before WireGuard setup.

.DESCRIPTION
    Run this ON the target workstation (or have wg-batch-enroll.ps1 run it remotely)
    BEFORE calling wg-workstation-setup.ps1.

    Checks:
      - Admin privileges
      - OS version + architecture
      - WireGuard already installed / already configured / tunnel already running
      - OpenSSH server state
      - Disk space
      - Internet connectivity (DNS + HTTPS)
      - UDP 51820 reachability to the hub (best-effort)
      - Outbound HTTPS to GitHub/AWS (needed for git pull + winget)
      - Existing VPN routes / conflicting 10.10.0.0/24 routes
      - Windows Firewall: WireGuard + OpenSSH rules
      - Required tools present (git, winget, aws)
      - Fleet SSH key in authorized_keys

.PARAMETER HubEndpoint
    WireGuard hub IP:port. Defaults to the fleet hub.

.PARAMETER ExpectedVpnIp
    The VPN IP that will be assigned (optional, for checking conflicts).

.PARAMETER SshKeyPubPath
    Local path to fleet_ed25519.pub to verify it is already in authorized_keys.

.PARAMETER Json
    Output a machine-readable JSON summary instead of colour text.

.EXAMPLE
    .\wg-pre-enroll-probe.ps1

    .\wg-pre-enroll-probe.ps1 -ExpectedVpnIp 10.10.0.3 -HubEndpoint 3.220.226.162:51820

    # Run remotely from fleet management host (inside wg-batch-enroll.ps1):
    ssh admin@ai01.bhss.edu.hk "powershell -NoProfile -File C:\...\wg-pre-enroll-probe.ps1 -Json"
#>

param(
    [string]$HubEndpoint    = "3.220.226.162:51820",
    [string]$ExpectedVpnIp  = "",
    [string]$SshKeyPubPath  = "",
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Result tracking ───────────────────────────────────────────────────

$results = [System.Collections.Generic.List[hashtable]]::new()

function Add-Check {
    param(
        [string]$Category,
        [string]$Check,
        [ValidateSet('PASS','WARN','FAIL','INFO')]
        [string]$Status,
        [string]$Detail = ""
    )
    $results.Add(@{ Category=$Category; Check=$Check; Status=$Status; Detail=$Detail })
}

function Write-Check {
    param($Category, $Check, $Status, $Detail)
    if ($Json) { return }
    $color = switch ($Status) {
        'PASS' { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        'INFO' { 'Cyan' }
    }
    $label = "[{0,-4}]" -f $Status
    $line  = "  $label  $($Category.PadRight(20)) $Check"
    if ($Detail) { $line += "  -- $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Check {
    param($Category, $Check, $Status, $Detail = "")
    Add-Check $Category $Check $Status $Detail
    Write-Check $Category $Check $Status $Detail
}

# ── Banner ────────────────────────────────────────────────────────────

if (-not $Json) {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  WireGuard Pre-Enrollment Probe" -ForegroundColor Cyan
    Write-Host "  Host: $env:COMPUTERNAME   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════
# 1. SYSTEM STATE
# ═══════════════════════════════════════════════════════════════════

if (-not $Json) { Write-Host "── SYSTEM ──────────────────────────────────────" -ForegroundColor White }

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { Check 'System' 'Admin privileges' 'PASS' 'Running as administrator' }
else          { Check 'System' 'Admin privileges' 'FAIL' 'Must run as Administrator for WireGuard install' }

# OS version
$os    = Get-CimInstance Win32_OperatingSystem
$osVer = "$($os.Caption) Build $($os.BuildNumber)"
$arch  = $env:PROCESSOR_ARCHITECTURE
$build = [int]$os.BuildNumber

if ($build -ge 17763) {
    Check 'System' 'OS version' 'PASS' "$osVer ($arch)"
} elseif ($build -ge 14393) {
    Check 'System' 'OS version' 'WARN' "$osVer -- WireGuard works but Win10 1607+ preferred"
} else {
    Check 'System' 'OS version' 'FAIL' "$osVer -- Windows 10 1803+ required for WireGuard kernel driver"
}

# Disk space (C:\ — need room for WireGuard installer + logs)
$drive = Get-PSDrive C -ErrorAction SilentlyContinue
if ($drive) {
    $freeGb = [math]::Round($drive.Free / 1GB, 1)
    if ($freeGb -ge 2)    { Check 'System' 'Disk space (C:\)' 'PASS' "${freeGb} GB free" }
    elseif ($freeGb -ge 0.5) { Check 'System' 'Disk space (C:\)' 'WARN' "${freeGb} GB free (low)" }
    else                  { Check 'System' 'Disk space (C:\)' 'FAIL' "${freeGb} GB free -- insufficient" }
}

# PowerShell version
$psVer = $PSVersionTable.PSVersion.ToString()
if ($PSVersionTable.PSVersion.Major -ge 5) {
    Check 'System' 'PowerShell version' 'PASS' "v$psVer"
} else {
    Check 'System' 'PowerShell version' 'WARN' "v$psVer -- PS 5.1+ recommended"
}

# ═══════════════════════════════════════════════════════════════════
# 2. WIREGUARD STATE
# ═══════════════════════════════════════════════════════════════════

if (-not $Json) { Write-Host ""; Write-Host "── WIREGUARD ───────────────────────────────────" -ForegroundColor White }

$wgExe    = 'C:\Program Files\WireGuard\wireguard.exe'
$wgTool   = 'C:\Program Files\WireGuard\wg.exe'
$confDir  = 'C:\Program Files\WireGuard\Data\Configurations'
$confFile = "$confDir\wg-fleet.conf"
$keyDir   = "$env:USERPROFILE\.wireguard"
$privKey  = "$keyDir\private.key"
$pubKey   = "$keyDir\public.key"

# WireGuard binary
if (Test-Path $wgExe) {
    $wgVersion = (& $wgExe /version 2>$null | Out-String).Trim()
    Check 'WireGuard' 'Binary installed' 'PASS' $wgVersion
} else {
    Check 'WireGuard' 'Binary installed' 'WARN' "Not found at $wgExe -- will be installed"
}

# wg.exe tool
if (Test-Path $wgTool) {
    Check 'WireGuard' 'wg.exe tool' 'PASS' "Found"
} else {
    Check 'WireGuard' 'wg.exe tool' 'WARN' "Not found -- part of WireGuard package"
}

# Existing tunnel config
if (Test-Path $confFile) {
    $confContent = Get-Content $confFile -Raw -ErrorAction SilentlyContinue
    $hasAddr  = $confContent -match 'Address\s*='
    $hasPeer  = $confContent -match '\[Peer\]'
    $hasPriv  = $confContent -match 'PrivateKey\s*='
    if ($hasAddr -and $hasPeer -and $hasPriv) {
        Check 'WireGuard' 'Tunnel config' 'WARN' "wg-fleet.conf already exists (will be overwritten)"
        # Extract address
        if ($confContent -match 'Address\s*=\s*(\S+)') {
            Check 'WireGuard' 'Existing tunnel IP' 'INFO' $Matches[1]
        }
    } else {
        Check 'WireGuard' 'Tunnel config' 'WARN' "wg-fleet.conf exists but incomplete"
    }
} else {
    Check 'WireGuard' 'Tunnel config' 'PASS' "Not present -- clean slate"
}

# Tunnel service running?
$tunnelSvc = Get-Service -Name 'WireGuardTunnel$wg-fleet' -ErrorAction SilentlyContinue
if ($tunnelSvc) {
    if ($tunnelSvc.Status -eq 'Running') {
        Check 'WireGuard' 'Tunnel service' 'WARN' "wg-fleet tunnel ALREADY RUNNING -- check if VPN is live"
    } else {
        Check 'WireGuard' 'Tunnel service' 'INFO' "Service exists, status: $($tunnelSvc.Status)"
    }
} else {
    Check 'WireGuard' 'Tunnel service' 'PASS' "Not installed -- ready for enrollment"
}

# Existing WireGuard key pair
if (Test-Path $privKey) {
    Check 'WireGuard' 'Existing key pair' 'WARN' "Keys at $keyDir will be reused (not regenerated)"
    if (Test-Path $pubKey) {
        $existingPub = (Get-Content $pubKey -Raw -ErrorAction SilentlyContinue).Trim()
        Check 'WireGuard' 'Existing public key' 'INFO' $existingPub
    }
} else {
    Check 'WireGuard' 'Existing key pair' 'PASS' "No prior keys -- fresh pair will be generated"
}

# ═══════════════════════════════════════════════════════════════════
# 3. NETWORK — INTERFACE
# ═══════════════════════════════════════════════════════════════════

if (-not $Json) { Write-Host ""; Write-Host "── NETWORK (INTERFACES) ────────────────────────" -ForegroundColor White }

$adapters = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' }
if ($adapters) {
    foreach ($a in $adapters) {
        $ip  = ($a.IPv4Address | Select-Object -First 1).IPAddress
        $gw  = $a.IPv4DefaultGateway.NextHop
        $ifc = $a.InterfaceAlias
        Check 'Network' "Interface: $ifc" 'INFO' "IP=$ip  GW=$gw"
    }
} else {
    Check 'Network' 'Active interfaces' 'FAIL' "No interfaces with a default gateway found"
}

# Check for conflicting 10.10.0.0/24 routes (not via WireGuard)
$vpnRoute = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.DestinationPrefix -like '10.10.0.*' -and $_.InterfaceAlias -notmatch -join('WireGuard','wg-fleet') }
if ($vpnRoute) {
    foreach ($r in $vpnRoute) {
        Check 'Network' 'Conflicting VPN route' 'WARN' "Route $($r.DestinationPrefix) via $($r.InterfaceAlias) (not WireGuard)"
    }
} else {
    Check 'Network' 'VPN route conflicts' 'PASS' "No conflicting 10.10.0.0/24 routes"
}

# Expected VPN IP conflict check
if ($ExpectedVpnIp) {
    $conflict = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $ExpectedVpnIp }
    if ($conflict) {
        Check 'Network' "IP conflict $ExpectedVpnIp" 'WARN' "Already assigned to interface: $($conflict.InterfaceAlias)"
    } else {
        Check 'Network' "IP conflict $ExpectedVpnIp" 'PASS' "Not in use"
    }
}

# ═══════════════════════════════════════════════════════════════════
# 4. NETWORK — CONNECTIVITY
# ═══════════════════════════════════════════════════════════════════

if (-not $Json) { Write-Host ""; Write-Host "── NETWORK (CONNECTIVITY) ──────────────────────" -ForegroundColor White }

# DNS resolution
$dnsTest = Resolve-DnsName 'google.com' -ErrorAction SilentlyContinue
if ($dnsTest) { Check 'Connectivity' 'DNS resolution' 'PASS' "google.com -> $($dnsTest[0].IPAddress)" }
else          { Check 'Connectivity' 'DNS resolution' 'FAIL' "Cannot resolve google.com" }

# HTTPS to internet
try {
    $http = Invoke-WebRequest -Uri 'https://google.com' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    Check 'Connectivity' 'HTTPS internet' 'PASS' "HTTP $($http.StatusCode)"
} catch {
    Check 'Connectivity' 'HTTPS internet' 'FAIL' $_.Exception.Message
}

# HTTPS to GitHub (git pull)
try {
    $gh = Invoke-WebRequest -Uri 'https://github.com' -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
    Check 'Connectivity' 'HTTPS GitHub' 'PASS' "HTTP $($gh.StatusCode)"
} catch {
    Check 'Connectivity' 'HTTPS GitHub' 'WARN' "Cannot reach github.com -- git pull may fail: $($_.Exception.Message)"
}

# TCP to hub IP (verifies routing; WireGuard uses UDP but TCP tells us IP is routable)
$hubIp   = ($HubEndpoint -split ':')[0]
$hubPort = if ($HubEndpoint -match ':(\d+)$') { [int]$Matches[1] } else { 51820 }

$tcpHub = Test-NetConnection -ComputerName $hubIp -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue 2>$null
if ($tcpHub) {
    Check 'Connectivity' "Hub TCP $hubIp :443" 'INFO' "TCP reachable (routing OK)"
} else {
    Check 'Connectivity' "Hub TCP $hubIp :443" 'INFO' "TCP :443 blocked (expected on EC2) -- routing may still be OK"
}

# UDP 51820 probe (best-effort via .NET UDP send + check for ICMP port-unreachable)
# We just confirm the IP is routable via a ping; UDP reachability is confirmed after tunnel up
$pingHub = Test-NetConnection -ComputerName $hubIp -InformationLevel Quiet -WarningAction SilentlyContinue 2>$null
if ($pingHub) {
    Check 'Connectivity' "Hub ICMP $hubIp" 'PASS' "Hub IP is pingable"
} else {
    Check 'Connectivity' "Hub ICMP $hubIp" 'WARN' "ICMP blocked -- UDP/51820 connectivity unconfirmed until tunnel up"
}

# ═══════════════════════════════════════════════════════════════════
# 5. FIREWALL
# ═══════════════════════════════════════════════════════════════════

if (-not $Json) { Write-Host ""; Write-Host "── FIREWALL ─────────────────────────────────────" -ForegroundColor White }

$fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
foreach ($fp in $fwProfiles) {
    $state = if ($fp.Enabled) { 'Enabled' } else { 'Disabled' }
    $status = if ($fp.Enabled) { 'INFO' } else { 'WARN' }
    Check 'Firewall' "Profile $($fp.Name)" $status $state
}

# WireGuard inbound rule
$wgFwRule = Get-NetFirewallRule -DisplayName '*WireGuard*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wgFwRule) {
    Check 'Firewall' 'WireGuard rule' 'PASS' "Rule '$($wgFwRule.DisplayName)' ($($wgFwRule.Action))"
} else {
    Check 'Firewall' 'WireGuard rule' 'WARN' "No WireGuard firewall rule found -- may need: New-NetFirewallRule -DisplayName WireGuard-UDP -Protocol UDP -LocalPort 51820 -Action Allow"
}

# OpenSSH inbound rule
$sshFwRule = Get-NetFirewallRule -DisplayName '*OpenSSH*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sshFwRule) {
    $sshFwRule = Get-NetFirewallRule -DisplayName '*SSH*' -ErrorAction SilentlyContinue | Select-Object -First 1
}
if ($sshFwRule) {
    Check 'Firewall' 'OpenSSH rule' 'PASS' "Rule '$($sshFwRule.DisplayName)' ($($sshFwRule.Action))"
} else {
    Check 'Firewall' 'OpenSSH rule' 'WARN' "No SSH firewall rule -- fleet SSH may be blocked post-VPN"
}

# ═══════════════════════════════════════════════════════════════════
# 6. OPENSSH
# ═══════════════════════════════════════════════════════════════════

if (-not $Json) { Write-Host ""; Write-Host "── OPENSSH ──────────────────────────────────────" -ForegroundColor White }

$sshd = Get-Service sshd -ErrorAction SilentlyContinue
if ($sshd) {
    if ($sshd.Status -eq 'Running') {
        Check 'OpenSSH' 'sshd service' 'PASS' "Running (StartType: $($sshd.StartType))"
    } else {
        Check 'OpenSSH' 'sshd service' 'WARN' "Installed but $($sshd.Status) -- fleet SSH will fail after VPN"
    }
    if ($sshd.StartType -ne 'Automatic') {
        Check 'OpenSSH' 'sshd auto-start' 'WARN' "StartType is $($sshd.StartType) -- should be Automatic"
    } else {
        Check 'OpenSSH' 'sshd auto-start' 'PASS' "Automatic"
    }
} else {
    Check 'OpenSSH' 'sshd service' 'WARN' "Not installed -- wg-workstation-setup.ps1 will install it"
}

# authorized_keys check for fleet key
$authKeysPath = "$env:USERPROFILE\.ssh\authorized_keys"
$adminAuthKeys = 'C:\ProgramData\ssh\administrators_authorized_keys'
if ($SshKeyPubPath -and (Test-Path $SshKeyPubPath)) {
    $fleetPub = (Get-Content $SshKeyPubPath -Raw -ErrorAction SilentlyContinue).Trim()
    $found = $false
    foreach ($akPath in @($authKeysPath, $adminAuthKeys)) {
        if (Test-Path $akPath) {
            $akContent = Get-Content $akPath -Raw -ErrorAction SilentlyContinue
            if ($akContent -and $akContent -like "*$($fleetPub.Split(' ')[1].Substring(0,20))*") {
                Check 'OpenSSH' 'Fleet key in authorized_keys' 'PASS' "Found in $akPath"
                $found = $true; break
            }
        }
    }
    if (-not $found) {
        Check 'OpenSSH' 'Fleet key in authorized_keys' 'FAIL' "Fleet pubkey NOT found -- SSH will be rejected. Add: $fleetPub"
    }
} else {
    # Just check if authorized_keys exist
    if (Test-Path $authKeysPath) {
        $lineCount = (Get-Content $authKeysPath -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
        Check 'OpenSSH' 'authorized_keys' 'INFO' "$authKeysPath ($lineCount keys)"
    } elseif (Test-Path $adminAuthKeys) {
        $lineCount = (Get-Content $adminAuthKeys -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
        Check 'OpenSSH' 'authorized_keys' 'INFO' "$adminAuthKeys ($lineCount keys)"
    } else {
        Check 'OpenSSH' 'authorized_keys' 'WARN' "No authorized_keys found -- fleet SSH key must be added before enrollment"
    }
}

# ═══════════════════════════════════════════════════════════════════
# 7. REQUIRED TOOLS
# ═══════════════════════════════════════════════════════════════════

if (-not $Json) { Write-Host ""; Write-Host "── REQUIRED TOOLS ───────────────────────────────" -ForegroundColor White }

$tools = @(
    @{ Name='git';    Required=$true;  Purpose='pull repo updates' }
    @{ Name='winget'; Required=$false; Purpose='install WireGuard if missing' }
    @{ Name='aws';    Required=$false; Purpose='SSM hub commands (not needed on workstation)' }
)

foreach ($t in $tools) {
    $cmd = Get-Command $t.Name -ErrorAction SilentlyContinue
    if ($cmd) {
        $ver = try { & $t.Name --version 2>$null | Select-Object -First 1 } catch { '' }
        Check 'Tools' $t.Name 'PASS' $ver
    } else {
        $lvl = if ($t.Required) { 'FAIL' } else { 'WARN' }
        Check 'Tools' $t.Name $lvl "Not found -- needed to $($t.Purpose)"
    }
}

# ═══════════════════════════════════════════════════════════════════
# 8. SUMMARY
# ═══════════════════════════════════════════════════════════════════

$passes = ($results | Where-Object { $_.Status -eq 'PASS' }).Count
$warns  = ($results | Where-Object { $_.Status -eq 'WARN' }).Count
$fails  = ($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$infos  = ($results | Where-Object { $_.Status -eq 'INFO' }).Count

$overall = if ($fails -gt 0) { 'FAIL' } elseif ($warns -gt 0) { 'WARN' } else { 'PASS' }

if ($Json) {
    @{
        host      = $env:COMPUTERNAME
        timestamp = (Get-Date -Format 'o')
        overall   = $overall
        summary   = @{ pass=$passes; warn=$warns; fail=$fails; info=$infos }
        checks    = $results
    } | ConvertTo-Json -Depth 6
    return
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host " SUMMARY" -ForegroundColor White

$summaryColor = switch ($overall) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } }
Write-Host "  Overall: $overall   PASS:$passes  WARN:$warns  FAIL:$fails  INFO:$infos" -ForegroundColor $summaryColor

if ($fails -gt 0) {
    Write-Host ""
    Write-Host "  BLOCKERS (must fix before enrollment):" -ForegroundColor Red
    $results | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
        Write-Host "    [$($_.Category)] $($_.Check): $($_.Detail)" -ForegroundColor Red
    }
}

if ($warns -gt 0) {
    Write-Host ""
    Write-Host "  WARNINGS (review before enrolling):" -ForegroundColor Yellow
    $results | Where-Object { $_.Status -eq 'WARN' } | ForEach-Object {
        Write-Host "    [$($_.Category)] $($_.Check): $($_.Detail)" -ForegroundColor Yellow
    }
}

Write-Host ""
switch ($overall) {
    'PASS' { Write-Host "  Machine is READY for WireGuard enrollment." -ForegroundColor Green }
    'WARN' { Write-Host "  Machine can proceed but review warnings above." -ForegroundColor Yellow }
    'FAIL' { Write-Host "  Enrollment BLOCKED -- resolve FAIL items first." -ForegroundColor Red }
}
Write-Host "═══════════════════════════════════════════════" -ForegroundColor White
Write-Host ""
