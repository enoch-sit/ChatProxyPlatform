#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Phase 2: Activate Local WireGuard
    
.DESCRIPTION
    Activates WireGuard on this machine using wg-quick and verifies connectivity.
    
.EXAMPLE
    .\phase2-activate-local-wireguard.ps1
    
.NOTES
    Requires:
    - WireGuard installed (https://www.wireguard.com/install/)
    - PowerShell running as Administrator
    - wg-fleet.conf present in current directory
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

function Write-OK   { param([string]$msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail { param([string]$msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Warn { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Step { param([string]$msg) Write-Host "`n$msg" -ForegroundColor Cyan -BackgroundColor Black }

Write-Host "`n════════════════════════════════════════════════════════════"
Write-Host "  Phase 2: Activate Local WireGuard" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════`n"

# Check admin
$admin = [Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544'
if (-not $admin) {
    Write-Fail "This script must run as Administrator"
    Write-Host "  >> Right-click PowerShell and select 'Run as Administrator'"
    exit 1
}
Write-OK "Running as Administrator"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.1 Check WireGuard Installation"
# ─────────────────────────────────────────────────────────────────────────────

$wg = Get-Command wg.exe -ErrorAction SilentlyContinue
if (-not $wg) {
    Write-Fail "WireGuard CLI (wg.exe) not found"
    Write-Host "  >> Download and install: https://www.wireguard.com/install/"
    Write-Host "  >> Restart PowerShell after installation"
    exit 1
}
Write-OK "WireGuard CLI found: $($wg.Source)"

$wgQuick = Get-Command wg-quick.cmd -ErrorAction SilentlyContinue
if (-not $wgQuick) {
    Write-Warn "wg-quick not found (may be in PATH)"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.2 Locate Configuration File"
# ─────────────────────────────────────────────────────────────────────────────

$confFile = Get-Item "wg-fleet.conf" -ErrorAction SilentlyContinue
if (-not $confFile) {
    Write-Fail "wg-fleet.conf not found in current directory"
    Write-Host "  Current dir: $(Get-Location)"
    Write-Host "  >> Make sure you're in the ChatProxy root directory"
    exit 1
}
Write-OK "Config found: $($confFile.FullName)"

# Read and display config
$confContent = Get-Content $confFile -Raw
Write-Host "`n  Config content:"
Write-Host "  ────────────────────────────────────"
$confContent -split '\n' | ForEach-Object { Write-Host "  $_" }
Write-Host "  ────────────────────────────────────"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.3 Check Current WireGuard Interfaces"
# ─────────────────────────────────────────────────────────────────────────────

try {
    $interfaces = wg show 2>&1
    if ($interfaces -match "Unable to access") {
        Write-Warn "WireGuard interfaces not accessible (may need activation)"
    } else {
        Write-OK "Current interfaces:"
        $interfaces | ForEach-Object { Write-Host "  $_" }
    }
} catch {
    Write-Warn "Could not list WireGuard interfaces: $_"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.4 Activate WireGuard Interface"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "  Activating wg-fleet..."

$result = wg-quick up $confFile.FullName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-OK "WireGuard activated successfully"
    Write-Host $result
} else {
    Write-Fail "Failed to activate WireGuard"
    Write-Host $result
    Write-Host "`n  >> Try manually via WireGuard GUI:"
    Write-Host "     1. Open WireGuard application"
    Write-Host "     2. Click 'Import' and select wg-fleet.conf"
    Write-Host "     3. Click 'Activate'"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.5 Verify Interface is Active"
# ─────────────────────────────────────────────────────────────────────────────

Start-Sleep -Seconds 2

$wgShow = wg show 2>&1
if ($wgShow -match "interface: wg-fleet") {
    Write-OK "Interface wg-fleet is active"
} else {
    Write-Warn "Interface status unclear: $wgShow"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.6 Check VPN IP Address"
# ─────────────────────────────────────────────────────────────────────────────

$ipconfig = ipconfig /all 2>&1
$vpnIp = $ipconfig | Select-String "10\.10\.0\."

if ($vpnIp) {
    Write-OK "VPN IP assigned:"
    $vpnIp | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Warn "VPN IP not found (check WireGuard status)"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.7 Check Route Table"
# ─────────────────────────────────────────────────────────────────────────────

$route = route print 2>&1 | Select-String "10\.10\.0"
if ($route) {
    Write-OK "VPN routes configured:"
    $route | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Warn "VPN routes not found"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "2.8 Summary"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n  WireGuard Status:"
wg show wg-fleet 2>&1 | ForEach-Object { Write-Host "  $_" }

Write-Host "`n  Next Steps:"
Write-Host "    1. Verify WireGuard is active:"
Write-Host "       wg show wg-fleet"
Write-Host ""
Write-Host "    2. Proceed to Phase 3: Test Connectivity"
Write-Host "       ping 10.10.0.1"
Write-Host "       ping 10.10.0.2"
Write-Host ""
Write-Host "    3. If pings fail, check:"
Write-Host "       - Windows Firewall (allow UDP 51820)"
Write-Host "       - AWS security group (Phase 1)"
Write-Host "       - WireGuard service running"
Write-Host ""
