<#
.SYNOPSIS
    Fleet management script — centrally manage Windows workstations over WireGuard VPN.

.DESCRIPTION
    Connects to workstations via SSH through the WireGuard tunnel and runs
    setup.ps1, patch.ps1, or diagnose.ps1 remotely.

    Prerequisites:
    - WireGuard tunnel active on this machine
    - SSH key distributed to workstations (fleet_ed25519)
    - OpenSSH client installed (Windows 10+ built-in)

.PARAMETER Action
    What to do: status, patch, health, setup, deploy-key, run-command

.PARAMETER Target
    Which workstation(s): 'all' (default) or a comma-separated list of names from fleet-inventory.json

.PARAMETER PatchMode
    Mode passed to patch.ps1 on remote machines: auto, quick, full

.PARAMETER Command
    Custom command to run on target workstations (used with -Action run-command)

.PARAMETER Inventory
    Path to fleet-inventory.json (default: ./fleet-inventory.json)

.EXAMPLE
    .\fleet.ps1 -Action status
    .\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode quick
    .\fleet.ps1 -Action health -Target all
    .\fleet.ps1 -Action run-command -Command "Get-Service docker"
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('status', 'patch', 'health', 'setup', 'deploy-key', 'run-command')]
    [string]$Action,

    [string]$Target = 'all',
    [ValidateSet('auto', 'quick', 'full')]
    [string]$PatchMode = 'auto',
    [string]$Command,
    [string]$Inventory = "$PSScriptRoot\fleet-inventory.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Colours ──────────────────────────────────────────────────────────
function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Step ($msg) { Write-Host "`n── $msg ──" -ForegroundColor Cyan }

# ── Load Inventory ───────────────────────────────────────────────────

if (-not (Test-Path $Inventory)) {
    Write-Fail "Inventory file not found: $Inventory"
    exit 1
}

$inv = Get-Content $Inventory -Raw | ConvertFrom-Json
$defaults = $inv.defaults

# Resolve SSH key path
$sshKey = $defaults.sshKeyPath -replace '^~', $env:USERPROFILE
if (-not (Test-Path $sshKey)) {
    Write-Warn "SSH key not found at $sshKey — some actions may fail"
}

# ── Resolve Target Workstations ──────────────────────────────────────

function Get-TargetWorkstations {
    $all = $inv.workstations | Where-Object { $_.enabled -ne $false }

    if ($Target -eq 'all') {
        return $all
    }

    $names = $Target -split ',' | ForEach-Object { $_.Trim() }
    $matched = $all | Where-Object { $_.name -in $names }

    $missing = $names | Where-Object { $_ -notin ($matched | ForEach-Object { $_.name }) }
    if ($missing) {
        Write-Warn "Unknown workstations: $($missing -join ', ')"
    }

    return $matched
}

# ── SSH Helper ───────────────────────────────────────────────────────

function Invoke-FleetSSH {
    param(
        [Parameter(Mandatory)] $Workstation,
        [Parameter(Mandatory)] [string]$RemoteCommand
    )

    $port = if ($Workstation.sshPort) { $Workstation.sshPort } else { $defaults.sshPort }
    $user = $Workstation.sshUser

    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new'
        '-o', 'ConnectTimeout=10'
        '-o', 'BatchMode=yes'
        '-i', $sshKey
        '-p', $port
        "$user@$($Workstation.wireguardIp)"
        $RemoteCommand
    )

    $result = & ssh @sshArgs 2>&1
    $exitCode = $LASTEXITCODE

    return @{
        Output   = ($result | Out-String).Trim()
        ExitCode = $exitCode
        Success  = ($exitCode -eq 0)
    }
}

# ── Action: status ───────────────────────────────────────────────────

function Invoke-Status {
    Write-Step "Fleet Status"

    $workstations = Get-TargetWorkstations
    $results = @()

    foreach ($ws in $workstations) {
        Write-Host "  Checking $($ws.name) ($($ws.wireguardIp))... " -NoNewline

        # Check WireGuard reachability
        $ping = Test-Connection -ComputerName $ws.wireguardIp -Count 1 -TimeoutSeconds 3 -Quiet -ErrorAction SilentlyContinue

        if (-not $ping) {
            Write-Fail "Unreachable"
            $results += [PSCustomObject]@{
                Name    = $ws.name
                IP      = $ws.wireguardIp
                Status  = 'OFFLINE'
                Version = '-'
                Docker  = '-'
            }
            continue
        }

        # Get version + Docker status via SSH
        $r = Invoke-FleetSSH -Workstation $ws -RemoteCommand @"
`$v = if (Test-Path C:\chatproxy\.local-version) { Get-Content C:\chatproxy\.local-version } else { 'unknown' }
`$d = (docker info --format '{{.ContainersRunning}} running' 2>`$null) ?? 'not-running'
Write-Output "`$v|`$d"
"@

        if ($r.Success) {
            $parts = $r.Output -split '\|', 2
            Write-OK "Online"
            $results += [PSCustomObject]@{
                Name    = $ws.name
                IP      = $ws.wireguardIp
                Status  = 'ONLINE'
                Version = $parts[0]
                Docker  = $parts[1]
            }
        }
        else {
            Write-Warn "SSH failed"
            $results += [PSCustomObject]@{
                Name    = $ws.name
                IP      = $ws.wireguardIp
                Status  = 'SSH_FAIL'
                Version = '-'
                Docker  = '-'
            }
        }
    }

    Write-Host ""
    $results | Format-Table -AutoSize
}

# ── Action: patch ────────────────────────────────────────────────────

function Invoke-Patch {
    Write-Step "Fleet Patch (mode=$PatchMode)"

    $workstations = Get-TargetWorkstations

    foreach ($ws in $workstations) {
        Write-Step "Patching $($ws.name)"

        $r = Invoke-FleetSSH -Workstation $ws -RemoteCommand @"
Set-Location C:\chatproxy
.\patch.ps1 -Mode $PatchMode 2>&1
"@

        if ($r.Success) {
            Write-OK "$($ws.name) patched successfully"
        }
        else {
            Write-Fail "$($ws.name) patch failed (exit $($r.ExitCode))"
        }

        if ($r.Output) {
            # Show last 20 lines of output
            $lines = $r.Output -split "`n"
            $tail = if ($lines.Count -gt 20) { $lines[-20..-1] } else { $lines }
            $tail | ForEach-Object { Write-Host "    $_" }
        }
    }
}

# ── Action: health ───────────────────────────────────────────────────

function Invoke-Health {
    Write-Step "Fleet Health Check"

    $workstations = Get-TargetWorkstations

    foreach ($ws in $workstations) {
        Write-Host "`n  ─ $($ws.name) ─"

        $r = Invoke-FleetSSH -Workstation $ws -RemoteCommand @"
Set-Location C:\chatproxy
.\diagnose.ps1 -Quick 2>&1
"@

        if ($r.Success) {
            Write-OK "$($ws.name) healthy"
        }
        else {
            Write-Warn "$($ws.name) has issues (exit $($r.ExitCode))"
        }

        if ($r.Output) {
            $r.Output -split "`n" | ForEach-Object { Write-Host "    $_" }
        }
    }
}

# ── Action: setup ────────────────────────────────────────────────────

function Invoke-Setup {
    Write-Step "Fleet Setup (initial provision)"

    $workstations = Get-TargetWorkstations

    foreach ($ws in $workstations) {
        Write-Step "Setting up $($ws.name)"

        $r = Invoke-FleetSSH -Workstation $ws -RemoteCommand @"
Set-Location C:\chatproxy
.\setup.ps1 -Unattended 2>&1
"@

        if ($r.Success) {
            Write-OK "$($ws.name) setup complete"
        }
        else {
            Write-Fail "$($ws.name) setup failed (exit $($r.ExitCode))"
        }

        if ($r.Output) {
            $lines = $r.Output -split "`n"
            $tail = if ($lines.Count -gt 30) { $lines[-30..-1] } else { $lines }
            $tail | ForEach-Object { Write-Host "    $_" }
        }
    }
}

# ── Action: deploy-key ──────────────────────────────────────────────

function Invoke-DeployKey {
    Write-Step "Deploy SSH Key to Workstations"

    $pubKey = "$sshKey.pub"
    if (-not (Test-Path $pubKey)) {
        Write-Host "  Generating SSH key pair for fleet management..."
        ssh-keygen -t ed25519 -f $sshKey -N '""' -C "fleet-management"

        if (-not (Test-Path $pubKey)) {
            Write-Fail "Key generation failed"
            return
        }
        Write-OK "Key pair generated: $sshKey"
    }

    $pubKeyContent = (Get-Content $pubKey -Raw).Trim()
    Write-Host "`n  Public key to install on each workstation:"
    Write-Host "  $pubKeyContent" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  On each Windows workstation, run:" -ForegroundColor Cyan
    Write-Host "    Add-Content `$env:USERPROFILE\.ssh\authorized_keys '$pubKeyContent'" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or for admin accounts (administrators_authorized_keys):" -ForegroundColor Cyan
    Write-Host "    Add-Content C:\ProgramData\ssh\administrators_authorized_keys '$pubKeyContent'" -ForegroundColor White
}

# ── Action: run-command ──────────────────────────────────────────────

function Invoke-RunCommand {
    if (-not $Command) {
        Write-Fail "Must specify -Command with -Action run-command"
        return
    }

    Write-Step "Run Command: $Command"

    $workstations = Get-TargetWorkstations

    foreach ($ws in $workstations) {
        Write-Host "`n  ─ $($ws.name) ─"

        $r = Invoke-FleetSSH -Workstation $ws -RemoteCommand $Command

        if ($r.Success) {
            Write-OK "Exit 0"
        }
        else {
            Write-Warn "Exit $($r.ExitCode)"
        }

        if ($r.Output) {
            $r.Output -split "`n" | ForEach-Object { Write-Host "    $_" }
        }
    }
}

# ── Dispatch ─────────────────────────────────────────────────────────

Write-Host "======================================" -ForegroundColor Cyan
Write-Host " Fleet Manager — ChatProxy Platform" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

switch ($Action) {
    'status'      { Invoke-Status }
    'patch'       { Invoke-Patch }
    'health'      { Invoke-Health }
    'setup'       { Invoke-Setup }
    'deploy-key'  { Invoke-DeployKey }
    'run-command' { Invoke-RunCommand }
}

Write-Host "`n── Fleet operation complete ──`n" -ForegroundColor Cyan
