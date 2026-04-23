<#
.SYNOPSIS
    Batch-enroll Windows workstations into the WireGuard fleet VPN.

.DESCRIPTION
    For each candidate workstation:
      1. SSH to it via its current reachable host (before VPN enrollment)
      2. Run wg-workstation-setup.ps1 remotely to generate keys + create tunnel config
      3. Collect the generated public key
      4. Assign the next available VPN IP in 10.10.0.0/24
      5. Update fleet-inventory.json with the new entry
      6. Push all new peers to the hub via AWS SSM (live wg set + save, no terraform)

    Idempotent: already-enrolled workstations (VPN IP reachable) are skipped.

.PARAMETER CandidatesFile
    Path to a JSON file listing candidates. Defaults to wg-candidates.json in the same folder.
    Format:
      [
        { "name": "BHSS-AI-SERVER0", "host": "ai01.bhss.edu.hk", "sshUser": "admin", "sshPort": 22 }
      ]

.PARAMETER Candidates
    Inline array of hashtables (alternative to -CandidatesFile).

.PARAMETER HubEndpoint
    WireGuard hub public IP:port. Defaults to fleet hub EIP.

.PARAMETER HubPublicKey
    WireGuard hub public key. Defaults to the known hub key.

.PARAMETER HubInstanceId
    AWS EC2 instance ID of the hub (for SSM). Defaults to known instance.

.PARAMETER SshKey
    Path to SSH private key for initial access. Defaults to ~/.ssh/fleet_ed25519.

.PARAMETER RepoPath
    Path to the ChatProxy repo on remote workstations.

.PARAMETER DryRun
    Print what would be done without executing.

.EXAMPLE
    # Enroll from candidates file
    .\wg-batch-enroll.ps1

    # Enroll BHSS inline
    .\wg-batch-enroll.ps1 -Candidates @(@{ name="BHSS-AI-SERVER0"; host="ai01.bhss.edu.hk"; sshUser="admin" })

    # Dry run to preview
    .\wg-batch-enroll.ps1 -DryRun
#>

param(
    [string]$CandidatesFile = "$PSScriptRoot\wg-candidates.json",

    [object[]]$Candidates,

    [string]$HubEndpoint    = "3.220.226.162:51820",
    [string]$HubPublicKey   = "cUDvoyHcJs7T3mpfQYA0xJ130/ff4udsNBchH+/l7T0=",
    [string]$HubInstanceId  = "i-021b5be52f91cc6fa",

    [string]$SshKey         = "$env:USERPROFILE\.ssh\fleet_ed25519",

    [string]$RepoPath       = 'C:\Users\admin\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform',

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$InventoryFile = "$PSScriptRoot\fleet-inventory.json"

function Write-OK   ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Step ($msg) { Write-Host "`n── $msg" -ForegroundColor Cyan }
function Write-Info ($msg) { Write-Host "  [INFO] $msg" -ForegroundColor White }
function Write-Dry  ($msg) { Write-Host "  [DRY]  $msg" -ForegroundColor DarkCyan }

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  WireGuard Batch Fleet Enrollment" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
if ($DryRun) { Write-Warn "DRY RUN MODE -- no changes will be made" }

# ── Load candidate list ───────────────────────────────────────────────

Write-Step "Loading enrollment candidates"

if (-not $Candidates) {
    if (Test-Path $CandidatesFile) {
        $Candidates = Get-Content $CandidatesFile -Raw | ConvertFrom-Json
        Write-Info "Loaded $(($Candidates).Count) candidates from $CandidatesFile"
    } else {
        Write-Fail "No candidates provided. Use -Candidates or create $CandidatesFile"
        Write-Host ""
        Write-Host "  Example wg-candidates.json:" -ForegroundColor Yellow
        Write-Host '  [{ "name": "BHSS-AI-SERVER0", "host": "ai01.bhss.edu.hk", "sshUser": "admin", "sshPort": 22 }]' -ForegroundColor White
        exit 1
    }
}

# ── Load fleet inventory ──────────────────────────────────────────────

Write-Step "Loading fleet inventory"

if (-not (Test-Path $InventoryFile)) {
    Write-Fail "fleet-inventory.json not found: $InventoryFile"
    exit 1
}

$inventory = Get-Content $InventoryFile -Raw | ConvertFrom-Json

# Build set of IPs already in use (hub + workstations)
$usedIps = @('10.10.0.1')  # hub
foreach ($ws in $inventory.workstations) {
    $usedIps += $ws.wireguardIp
}
Write-Info "VPN IPs already in use: $($usedIps -join ', ')"

# ── Validate SSH key ──────────────────────────────────────────────────

Write-Step "Validating SSH key"

if (-not (Test-Path $SshKey)) {
    Write-Fail "SSH key not found: $SshKey"
    Write-Host "  Generate one with: ssh-keygen -t ed25519 -f $SshKey -C fleet-management"
    exit 1
}
Write-OK "SSH key found: $SshKey"

# ── Helper: assign next available VPN IP ─────────────────────────────

function Get-NextVpnIp {
    for ($i = 2; $i -le 254; $i++) {
        $candidate = "10.10.0.$i"
        if ($usedIps -notcontains $candidate) {
            return $candidate
        }
    }
    Write-Fail "No available IPs in 10.10.0.0/24"
    exit 1
}

# ── Helper: SSH to pre-VPN host ───────────────────────────────────────

function Invoke-InitialSSH {
    param(
        [string]$Host,
        [string]$User,
        [int]$Port = 22,
        [string]$RemoteCommand
    )

    $bytes   = [System.Text.Encoding]::Unicode.GetBytes($RemoteCommand)
    $encoded = [Convert]::ToBase64String($bytes)

    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new'
        '-o', 'ConnectTimeout=15'
        '-o', 'BatchMode=yes'
        '-i', $SshKey
        '-p', $Port
        "$User@$Host"
        "powershell -NoProfile -EncodedCommand $encoded"
    )

    $output  = & ssh @sshArgs 2>&1
    $exit    = $LASTEXITCODE

    return @{ Output = ($output | Out-String).Trim(); ExitCode = $exit; Success = ($exit -eq 0) }
}

# ── Helper: check if VPN IP is already reachable ─────────────────────

function Test-VpnReachable {
    param([string]$Ip)
    $null = ping -n 1 -w 2000 $Ip 2>$null
    return $LASTEXITCODE -eq 0
}

# ── Main enrollment loop ──────────────────────────────────────────────

$newPeers   = @()   # peers to push to hub
$enrolledWs = @()   # new inventory entries

Write-Step "Enrolling candidates"

foreach ($c in $Candidates) {
    $name    = $c.name
    $host    = $c.host
    $user    = if ($c.sshUser) { $c.sshUser } else { 'admin' }
    $port    = if ($c.sshPort) { [int]$c.sshPort } else { 22 }

    Write-Host ""
    Write-Host "  ─ $name ($host) ─" -ForegroundColor Cyan

    # Check if already enrolled in inventory with matching name
    $existing = $inventory.workstations | Where-Object { $_.name -eq $name }
    if ($existing) {
        $vpnIp = $existing.wireguardIp
        if (Test-VpnReachable $vpnIp) {
            Write-OK "$name already enrolled and VPN reachable at $vpnIp -- skipping"
            continue
        } else {
            Write-Warn "$name in inventory but VPN unreachable at $vpnIp -- re-enrolling"
        }
    }

    # Assign VPN IP
    $vpnIp = if ($existing -and $existing.wireguardIp) { $existing.wireguardIp } else { Get-NextVpnIp }
    $usedIps += $vpnIp
    Write-Info "Assigned VPN IP: $vpnIp"

    if ($DryRun) {
        Write-Dry "Would SSH to $user@${host}:$port and run wg-workstation-setup.ps1 -MyIP $vpnIp/24"
        Write-Dry "Would add peer to fleet-inventory.json and hub via SSM"
        $enrolledWs += @{ name=$name; wireguardIp=$vpnIp; host=$host; sshUser=$user; sshPort=$port; publicKey="DRY-RUN" }
        continue
    }

    # Test SSH reachability
    Write-Info "Testing SSH to $user@${host}:$port ..."
    $ping = Invoke-InitialSSH -Host $host -User $user -Port $port -RemoteCommand 'Write-Output "SSH_OK"'
    if (-not $ping.Success) {
        Write-Fail "Cannot SSH to $host -- skipping. Verify key is deployed and host is reachable."
        Write-Warn "  Deploy key first: Add fleet_ed25519.pub to $host authorized_keys"
        continue
    }
    Write-OK "SSH reachable"

    # ── Run pre-enrollment probe on remote machine ────────────────
    Write-Info "Running pre-enrollment probe on $name ..."
    $probeCmd = @"
`$probeScript = '$RepoPath\wg-pre-enroll-probe.ps1'
if (Test-Path `$probeScript) {
    & `$probeScript -HubEndpoint '$HubEndpoint' -ExpectedVpnIp '$vpnIp' -Json 2>&1
} else {
    Write-Output '{"overall":"SKIP","summary":{"fail":0,"warn":0},"message":"probe script not found"}'
}
"@

    $probe = Invoke-InitialSSH -Host $host -User $user -Port $port -RemoteCommand $probeCmd
    $probeJson = $null
    try {
        # Extract JSON block from output (may have noise before/after)
        $jsonLine = $probe.Output -split "`n" | Where-Object { $_ -match '^\s*\{' } | Select-Object -First 1
        if ($jsonLine) { $probeJson = $jsonLine | ConvertFrom-Json }
    } catch { }

    if ($probeJson) {
        $po = $probeJson.overall
        $pf = $probeJson.summary.fail
        $pw = $probeJson.summary.warn
        if ($po -eq 'FAIL') {
            Write-Fail "Pre-enrollment probe FAILED ($pf blocker(s)) on $name -- skipping"
            if ($probeJson.checks) {
                $probeJson.checks | Where-Object { $_.Status -eq 'FAIL' } | ForEach-Object {
                    Write-Host "    [BLOCKER] $($_.Category): $($_.Check) -- $($_.Detail)" -ForegroundColor Red
                }
            }
            continue
        } elseif ($po -eq 'WARN') {
            Write-Warn "Pre-enrollment probe: $pw warning(s) on $name -- proceeding with caution"
            if ($probeJson.checks) {
                $probeJson.checks | Where-Object { $_.Status -eq 'WARN' } | ForEach-Object {
                    Write-Host "    [WARN] $($_.Category): $($_.Check) -- $($_.Detail)" -ForegroundColor Yellow
                }
            }
        } elseif ($po -eq 'PASS') {
            Write-OK "Pre-enrollment probe PASS on $name"
        } else {
            Write-Info "Probe result: $po (skipped or not found) -- continuing"
        }
    } else {
        Write-Warn "Could not parse probe output -- continuing anyway"
        if ($probe.Output) {
            $probe.Output -split "`n" | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
    }

    # Run wg-workstation-setup.ps1 on remote machine
    Write-Info "Running WireGuard setup on $name ..."
    $setupCmd = @"
Set-Location '$RepoPath'
if (-not (Test-Path '.\wg-workstation-setup.ps1')) {
    Write-Output 'SETUP_SCRIPT_MISSING'
    exit 1
}
.\wg-workstation-setup.ps1 ``
    -HubEndpoint '$HubEndpoint' ``
    -HubPublicKey '$HubPublicKey' ``
    -MyIP '$vpnIp/24' ``
    -TunnelName 'wg-fleet' 2>&1
"@

    $setup = Invoke-InitialSSH -Host $host -User $user -Port $port -RemoteCommand $setupCmd

    if ($setup.Output -match 'SETUP_SCRIPT_MISSING') {
        Write-Fail "wg-workstation-setup.ps1 not found at $RepoPath on $name"
        Write-Warn "  Git pull the repo first: cd $RepoPath; git pull origin bhss"
        continue
    }

    if (-not $setup.Success) {
        Write-Fail "WireGuard setup failed on $name (exit $($setup.ExitCode))"
        $setup.Output -split "`n" | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" }
        continue
    }

    # Extract public key from output (line after "Your WireGuard public key:")
    $pubKey = $null
    $lines  = $setup.Output -split "`n"
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i] -match 'WireGuard public key') {
            $pubKey = $lines[$i + 1].Trim()
            break
        }
    }
    # Fallback: look for a base64 key-shaped line (44 chars ending in =)
    if (-not $pubKey) {
        $pubKey = $lines | Where-Object { $_ -match '^[A-Za-z0-9+/]{43}=$' } | Select-Object -Last 1
        if ($pubKey) { $pubKey = $pubKey.Trim() }
    }

    if (-not $pubKey) {
        Write-Fail "Could not extract public key from setup output on $name"
        Write-Warn "  Last 10 lines of output:"
        $lines | Select-Object -Last 10 | ForEach-Object { Write-Host "    $_" }
        continue
    }
    Write-OK "Public key: $pubKey"

    # Activate the WireGuard tunnel on the workstation
    Write-Info "Activating WireGuard tunnel on $name ..."
    $activateCmd = @'
$confPath = "C:\Program Files\WireGuard\Data\Configurations\wg-fleet.conf"
if (-not (Test-Path $confPath)) { Write-Output "CONF_MISSING"; exit 1 }
$svc = Get-Service -Name "WireGuardTunnel`$wg-fleet" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Output "ALREADY_RUNNING"
} else {
    & 'C:\Program Files\WireGuard\wireguard.exe' /installtunnelservice $confPath
    Start-Sleep -Seconds 3
    $svc = Get-Service -Name "WireGuardTunnel`$wg-fleet" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { Write-Output "STARTED" } else { Write-Output "START_FAILED" }
}
'@

    $activate = Invoke-InitialSSH -Host $host -User $user -Port $port -RemoteCommand $activateCmd
    if ($activate.Output -match 'ALREADY_RUNNING|STARTED') {
        Write-OK "WireGuard tunnel active on $name"
    } elseif ($activate.Output -match 'CONF_MISSING') {
        Write-Warn "Tunnel config missing -- setup may have failed"
    } else {
        Write-Warn "Could not confirm tunnel status: $($activate.Output)"
    }

    $newPeers   += @{ name=$name; publicKey=$pubKey; allowedIp="$vpnIp/32" }
    $enrolledWs += @{
        name        = $name
        description = "$name enrolled $(Get-Date -Format 'yyyy-MM-dd')"
        wireguardIp = $vpnIp
        sshUser     = $user
        sshPort     = $port
        role        = "workstation"
        publicKey   = $pubKey
        services    = @("auth-service","accounting-service","bridge","flowise","flowise-proxy-service-py")
        enabled     = $true
    }

    Write-OK "$name enrolled (VPN IP: $vpnIp)"
}

# ── Update fleet-inventory.json ───────────────────────────────────────

if ($enrolledWs.Count -gt 0) {
    Write-Step "Updating fleet-inventory.json"

    foreach ($ws in $enrolledWs) {
        $existing = $inventory.workstations | Where-Object { $_.name -eq $ws.name }
        if ($existing) {
            # Update existing entry
            $existing.wireguardIp = $ws.wireguardIp
            if (-not $ws.publicKey.StartsWith('DRY')) { $existing | Add-Member -Force -NotePropertyName 'publicKey' -NotePropertyValue $ws.publicKey }
            Write-Info "Updated existing entry: $($ws.name)"
        } else {
            # Add new entry
            $entry = [PSCustomObject]$ws
            $allWs = [System.Collections.Generic.List[object]]($inventory.workstations)
            $allWs.Add($entry)
            $inventory.workstations = $allWs.ToArray()
            Write-Info "Added new entry: $($ws.name)"
        }
    }

    if (-not $DryRun) {
        $inventory | ConvertTo-Json -Depth 10 | Set-Content $InventoryFile -Encoding UTF8
        Write-OK "fleet-inventory.json updated"
    } else {
        Write-Dry "Would update fleet-inventory.json with $($enrolledWs.Count) entries"
    }
}

# ── Push new peers to hub via AWS SSM ────────────────────────────────

if ($newPeers.Count -gt 0 -and -not $DryRun) {
    Write-Step "Pushing $($newPeers.Count) new peer(s) to hub via SSM"

    # Build shell commands to add each peer live then persist
    $peerCmds = $newPeers | ForEach-Object {
        "wg set wg0 peer $($_.publicKey) allowed-ips $($_.allowedIp)"
    }
    $peerCmds += "wg-quick save wg0"
    $peerCmds += "echo 'Hub peer update complete'"

    $ssmCommands = $peerCmds | ConvertTo-Json -Compress

    Write-Info "Sending SSM command to hub $HubInstanceId ..."

    $ssmResult = aws ssm send-command `
        --instance-id $HubInstanceId `
        --document-name "AWS-RunShellScript" `
        --parameters "commands=$ssmCommands" `
        --region us-east-1 `
        --output json 2>&1 | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0 -or -not $ssmResult.Command) {
        Write-Fail "SSM command failed. Push peers to hub manually:"
        foreach ($p in $newPeers) {
            Write-Host "  wg set wg0 peer $($p.publicKey) allowed-ips $($p.allowedIp)" -ForegroundColor Yellow
        }
        Write-Host "  wg-quick save wg0" -ForegroundColor Yellow
    } else {
        $cmdId = $ssmResult.Command.CommandId
        Write-OK "SSM command sent: $cmdId"
        Write-Info "Check status: aws ssm get-command-invocation --command-id $cmdId --instance-id $HubInstanceId --region us-east-1"

        # Wait up to 30s for completion
        $waited = 0
        do {
            Start-Sleep -Seconds 5
            $waited += 5
            $inv = aws ssm get-command-invocation --command-id $cmdId --instance-id $HubInstanceId --region us-east-1 --output json 2>$null | ConvertFrom-Json
            $status = $inv.Status
        } while ($status -in @('Pending','InProgress') -and $waited -lt 30)

        if ($status -eq 'Success') {
            Write-OK "Hub updated successfully -- new peers are live"
        } else {
            Write-Warn "SSM status: $status (may still be running)"
            Write-Info "Check: aws ssm get-command-invocation --command-id $cmdId --instance-id $HubInstanceId --region us-east-1"
        }
    }
} elseif ($newPeers.Count -gt 0 -and $DryRun) {
    Write-Step "Would push these peers to hub via SSM:"
    foreach ($p in $newPeers) {
        Write-Dry "  wg set wg0 peer $($p.publicKey) allowed-ips $($p.allowedIp)"
    }
    Write-Dry "  wg-quick save wg0"
}

# ── Summary ───────────────────────────────────────────────────────────

Write-Step "Enrollment Summary"
Write-Host ""

if ($enrolledWs.Count -eq 0) {
    Write-Info "No new workstations enrolled (all already up or skipped)"
} else {
    Write-Host "  Enrolled workstations:" -ForegroundColor Green
    foreach ($ws in $enrolledWs) {
        Write-Host ("  {0,-30} VPN: {1,-15} Key: {2}" -f $ws.name, $ws.wireguardIp, ($ws.publicKey -replace 'DRY-RUN','(dry run)'))
    }
}

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    1. Verify VPN: ping 10.10.0.1 from each enrolled workstation"
Write-Host "    2. Run fleet status: .\fleet.ps1 -Action status"
Write-Host "    3. Run probe: probe_and_fix.bat (on each workstation)"
Write-Host ""

Write-Host "── Batch enrollment complete ──`n" -ForegroundColor Cyan
