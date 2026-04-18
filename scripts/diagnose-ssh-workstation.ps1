<#
.SYNOPSIS
    Run on the REMOTE workstation to diagnose SSH key authentication issues.
    Must be run as Administrator.
#>

$ErrorActionPreference = 'Continue'
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " SSH Diagnostics -- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host " Computer: $env:COMPUTERNAME  User: $env:USERNAME" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ── 1. Service Status ─────────────────────────────────────────────
Write-Host "`n[1] SSHD SERVICE" -ForegroundColor Yellow
Get-Service sshd | Format-Table Name, Status, StartType -AutoSize
Get-WmiObject Win32_Service -Filter "Name='sshd'" | Select-Object Name, State, PathName | Format-List

# ── 2. Listening Ports ─────────────────────────────────────────────
Write-Host "[2] LISTENING ON PORT 22" -ForegroundColor Yellow
netstat -an | findstr ":22 "

# ── 3. User Info ──────────────────────────────────────────────────
Write-Host "`n[3] USER INFO" -ForegroundColor Yellow
Write-Host "Current user: $env:USERDOMAIN\$env:USERNAME"
Write-Host "Home dir: $env:USERPROFILE"
Write-Host "Is admin:"
net localgroup Administrators 2>&1 | ForEach-Object { Write-Host "  $_" }

# ── 4. Firewall Rules ────────────────────────────────────────────
Write-Host "`n[4] FIREWALL RULES FOR PORT 22" -ForegroundColor Yellow
Get-NetFirewallRule -Direction Inbound | Where-Object {
    $portFilter = $_ | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $portFilter.LocalPort -eq '22' -or $_.DisplayName -match 'SSH|OpenSSH'
} | ForEach-Object {
    $profile = ($_ | Get-NetFirewallProfile -ErrorAction SilentlyContinue).Name -join ','
    [PSCustomObject]@{
        Name        = $_.Name
        DisplayName = $_.DisplayName
        Enabled     = $_.Enabled
        Action      = $_.Action
        Profile     = $profile
    }
} | Format-Table -AutoSize

# ── 5. sshd_config (full) ────────────────────────────────────────
Write-Host "[5] SSHD_CONFIG (non-comment lines)" -ForegroundColor Yellow
$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (Test-Path $sshdConfig) {
    Get-Content $sshdConfig | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) {
            Write-Host "  $line"
        }
    }
    Write-Host "`n  --- Full Match block context (last 30 lines) ---"
    Get-Content $sshdConfig | Select-Object -Last 30 | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "  FILE NOT FOUND: $sshdConfig" -ForegroundColor Red
}

# ── 6. Key Files ─────────────────────────────────────────────────
Write-Host "`n[6] KEY FILES" -ForegroundColor Yellow

$adminKeys = "C:\ProgramData\ssh\administrators_authorized_keys"
$userKeys = "$env:USERPROFILE\.ssh\authorized_keys"

foreach ($f in @($adminKeys, $userKeys)) {
    Write-Host "`n  File: $f"
    if (Test-Path $f) {
        Write-Host "  EXISTS: Yes"
        Write-Host "  Content:"
        Get-Content $f | ForEach-Object { Write-Host "    $_" }
        Write-Host "  Permissions:"
        icacls $f 2>&1 | ForEach-Object { Write-Host "    $_" }
        Write-Host "  Owner:"
        $acl = Get-Acl $f
        Write-Host "    $($acl.Owner)"
        Write-Host "  Inheritance disabled: $($acl.AreAccessRulesProtected)"
    } else {
        Write-Host "  EXISTS: No" -ForegroundColor Red
    }
}

# ── 7. Host Keys ────────────────────────────────────────────────
Write-Host "`n[7] HOST KEYS" -ForegroundColor Yellow
Get-ChildItem "C:\ProgramData\ssh\ssh_host_*" -ErrorAction SilentlyContinue | ForEach-Object {
    $acl = Get-Acl $_.FullName
    Write-Host "  $($_.Name) | Owner: $($acl.Owner) | Protected: $($acl.AreAccessRulesProtected)"
}

# ── 8. SSHD Logs ────────────────────────────────────────────────
Write-Host "`n[8] RECENT SSHD EVENT LOG (last 20 entries)" -ForegroundColor Yellow
try {
    Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 20 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, Message -Wrap -AutoSize
} catch {
    Write-Host "  OpenSSH/Operational log not available, trying Application log..."
    Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='sshd'; StartTime=(Get-Date).AddHours(-1)} -MaxEvents 20 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, Message -Wrap -AutoSize
}

# ── 9. SSHD debug output ────────────────────────────────────────
Write-Host "`n[9] SSHD LOG FILE (if exists)" -ForegroundColor Yellow
$logFiles = @("C:\ProgramData\ssh\logs\sshd.log", "C:\ProgramData\ssh\sshd.log")
foreach ($lf in $logFiles) {
    if (Test-Path $lf) {
        Write-Host "  Found: $lf"
        Get-Content $lf -Tail 30 | ForEach-Object { Write-Host "    $_" }
    }
}

# ── 10. WireGuard Interface ─────────────────────────────────────
Write-Host "`n[10] NETWORK INTERFACES" -ForegroundColor Yellow
Get-NetConnectionProfile | Format-Table Name, InterfaceAlias, NetworkCategory -AutoSize
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '10.10.0.*' -or $_.InterfaceAlias -match 'wg' } |
    Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize

# ── 11. Test local SSH ───────────────────────────────────────────
Write-Host "[11] LOCAL SSH TEST (localhost)" -ForegroundColor Yellow
$tcp = New-Object System.Net.Sockets.TcpClient
try {
    $tcp.Connect("127.0.0.1", 22)
    Write-Host "  localhost:22 OPEN" -ForegroundColor Green
    $tcp.Close()
} catch {
    Write-Host "  localhost:22 CLOSED" -ForegroundColor Red
}

# ── 12. Default shell ───────────────────────────────────────────
Write-Host "`n[12] DEFAULT SHELL" -ForegroundColor Yellow
$regPath = "HKLM:\SOFTWARE\OpenSSH"
if (Test-Path $regPath) {
    $shell = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).DefaultShell
    Write-Host "  DefaultShell: $shell"
} else {
    Write-Host "  No DefaultShell registry key (using default cmd.exe)"
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " DIAGNOSTICS COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
