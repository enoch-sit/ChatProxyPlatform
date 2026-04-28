#!/usr/bin/env pwsh
<#
.SYNOPSIS
    diagnose-ssh-firewall.ps1 - Diagnose SSH connectivity and firewall issues
    
.DESCRIPTION
    Tests SSH service configuration, firewall rules, and network connectivity
    to identify why SSH might be unreachable from remote machines.
    
.EXAMPLE
    .\diagnose-ssh-firewall.ps1 | Tee-Object -FilePath ssh-firewall-diagnosis.log
    
.NOTES
    Run on the workstation to diagnose SSH connectivity issues
#>

$ErrorActionPreference = "Continue"

function Write-Header {
    param([string]$msg)
    Write-Host "`n=========================================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
}

function Write-Section {
    param([string]$msg)
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor Yellow
}

function Write-Check {
    param([string]$name, [bool]$status, [string]$details = "")
    $symbol = if ($status) { "[OK]" } else { "[FAIL]" }
    $color = if ($status) { "Green" } else { "Red" }
    Write-Host "$symbol $name" -ForegroundColor $color
    if ($details) { Write-Host "   $details" -ForegroundColor Gray }
}

Write-Header "SSH & FIREWALL DIAGNOSTIC"

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "SSH SERVICE STATUS"
# ──────────────────────────────────────────────────────────────────────────────
$sshService = Get-Service sshd -ErrorAction SilentlyContinue
Write-Host "Service Name: $($sshService.Name)"
Write-Host "Service Status: $($sshService.Status)"
Write-Host "Start Type: $($sshService.StartType)"
Write-Check "SSH Service Running" ($sshService.Status -eq "Running") ""

if ($sshService.Status -ne "Running") {
    Write-Host "   [FIX] Start SSH service:"
    Write-Host "   Start-Service sshd"
    Write-Host "   Set-Service -Name sshd -StartupType Automatic"
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "SSH CONFIGURATION"
# ──────────────────────────────────────────────────────────────────────────────
$sshConfigPath = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshConfigPath) {
    Write-Host "SSHD Config file: $sshConfigPath`n"
    
    $configContent = Get-Content $sshConfigPath | Where-Object { $_ -match "^[^#]" -and $_ -notmatch "^\\s*$" }
    $configContent | Select-Object -First 20 | ForEach-Object {
        Write-Host "  $_"
    }
    
    # Check if listening on all addresses
    $listenOnAny = Get-Content $sshConfigPath | Where-Object { $_ -match "ListenAddress 0.0.0.0|ListenAddress ::|^#.*ListenAddress" }
    Write-Host "`nListenAddress config:"
    $listenOnAny | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "SSHD Config not found at $sshConfigPath"
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "LISTENING ON PORT 22"
# ──────────────────────────────────────────────────────────────────────────────
$listening = Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Check "Port 22 Listening" $true "$(($listening | Measure-Object).Count) connections"
    $listening | Select-Object LocalAddress, LocalPort, OwningProcess | ForEach-Object {
        $procName = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name
        Write-Host "   $($_.LocalAddress):$($_.LocalPort) <- PID $($_.OwningProcess) ($procName)"
    }
} else {
    Write-Check "Port 22 Listening" $false "No connections found"
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "FIREWALL STATUS"
# ──────────────────────────────────────────────────────────────────────────────
$fwStatus = Get-NetFirewallProfile -All | Select-Object Name, Enabled | Format-List | Out-String
Write-Host $fwStatus

$fwEnabled = (Get-NetFirewallProfile -Profile Domain, Public, Private | Where-Object { $_.Enabled }).Count -gt 0
Write-Check "Windows Firewall Enabled" $fwEnabled ""

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "SSH-RELATED FIREWALL RULES (Inbound)"
# ──────────────────────────────────────────────────────────────────────────────
$sshRules = Get-NetFirewallRule -DisplayName "*SSH*" -Direction Inbound -ErrorAction SilentlyContinue | Select-Object DisplayName, Enabled, Action, Direction | Format-Table | Out-String
Write-Host $sshRules

# Also check port-based rules for port 22
Write-Host "Port 22 firewall rules:"
$portRules = Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Where-Object {
    Get-NetFirewallPortFilter -AssociatedRule $_ | Where-Object { $_.LocalPort -eq 22 }
}

if ($portRules) {
    $portRules | ForEach-Object {
        Write-Host "  DisplayName: $($_.DisplayName)"
        Write-Host "    Enabled: $($_.Enabled)"
        Write-Host "    Action: $($_.Action)"
        Get-NetFirewallPortFilter -AssociatedRule $_ | ForEach-Object {
            Write-Host "    Port: $($_.LocalPort), Protocol: $($_.Protocol)"
        }
        Write-Host ""
    }
} else {
    Write-Host "  [WARN] No explicit port 22 rules found in firewall"
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "WINDOWS FIREWALL RULES FOR SSHD (netsh)"
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "All rules matching 'ssh' (name or program):"
$netshRules = & netsh advfirewall firewall show rule name=all 2>$null | Select-String -Pattern "Rule Name:|Enabled:|Direction:|Action:" | Select-Object -First 50 | Out-String
Write-Host $netshRules

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "TEST SSH LOCALLY"
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "Attempting to connect to localhost:22..."
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $tcpClient.Connect("127.0.0.1", 22)
    if ($tcpClient.Connected) {
        Write-Check "Local SSH Connection" $true "Successfully connected to 127.0.0.1:22"
        $tcpClient.Close()
        
        # Try banner grab
        $stream = $tcpClient.GetStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $banner = $reader.ReadLine()
        Write-Host "   SSH Banner: $banner"
    } else {
        Write-Check "Local SSH Connection" $false "Connection not established"
    }
} catch {
    Write-Check "Local SSH Connection" $false $_.Exception.Message
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "SSH AUTHORIZED KEYS"
# ──────────────────────────────────────────────────────────────────────────────
$fleetUserPath = "C:\Users\fleet"
$authorizedKeysPath = "$fleetUserPath\.ssh\authorized_keys"

if (Test-Path $authorizedKeysPath) {
    $keyCount = (Get-Content $authorizedKeysPath | Measure-Object -Line).Lines
    Write-Check "Authorized Keys Exist" $true "File: $authorizedKeysPath ($keyCount keys)"
    Write-Host "First key (truncated):"
    (Get-Content $authorizedKeysPath | Select-Object -First 1).Substring(0, 80) + "..." | Write-Host
} else {
    Write-Check "Authorized Keys Exist" $false "File not found: $authorizedKeysPath"
    Write-Host "   [FIX] Create SSH keys for fleet user:"
    Write-Host "   ssh-keygen -t ed25519 -f C:\Users\fleet\.ssh\fleet_ed25519 -N '' -C 'fleet@workstation'"
    Write-Host "   Add public key to authorized_keys"
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "NETWORK INTERFACES"
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "All interfaces:"
Get-NetIPConfiguration | Select-Object -Property InterfaceAlias, IPv4Address, IPv6LinkLocalAddress | Format-Table | Out-String | Write-Host

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "VPN INTERFACE (wg-fleet)"
# ──────────────────────────────────────────────────────────────────────────────
$wgInterface = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -eq "wg-fleet" }
if ($wgInterface) {
    Write-Check "WireGuard VPN Active" $true "IP: $($wgInterface.IPv4Address.IPAddress)"
    Write-Host "   Status: $($wgInterface.NetAdapter.Status)"
    Write-Host "   Description: $($wgInterface.InterfaceDescription)"
} else {
    Write-Check "WireGuard VPN Active" $false "Interface not found"
}

# ──────────────────────────────────────────────────────────────────────────────
Write-Section "RECOMMENDED FIXES"
# ──────────────────────────────────────────────────────────────────────────────

Write-Host "`nIf SSH is not accessible remotely, apply these fixes in order:`n"

Write-Host "1. Ensure SSH service is running:"
Write-Host "   Start-Service sshd"
Write-Host "   Set-Service -Name sshd -StartupType Automatic`n"

Write-Host "2. Create firewall rule for SSH (if missing):"
Write-Host "   New-NetFirewallRule -Name 'SSH' -DisplayName 'SSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow`n"

Write-Host "3. Verify SSH config allows remote connections:"
Write-Host "   - File: $sshConfigPath"
Write-Host "   - Should contain or NOT be commented out: ListenAddress 0.0.0.0"
Write-Host "   - Should contain or NOT be commented out: Port 22`n"

Write-Host "4. Ensure authorized_keys file exists and contains management machine public key:"
Write-Host "   Path: $authorizedKeysPath`n"

Write-Host "5. After changes, restart SSH service:"
Write-Host "   Restart-Service sshd`n"

Write-Host "6. Test from management machine:"
Write-Host "   ssh -i ~/.ssh/fleet_ed25519 fleet@10.10.0.2 'echo SSH OK'`n"

Write-Header "DIAGNOSIS COMPLETE"
Write-Host "Save this output and share with management team for analysis.`n"
