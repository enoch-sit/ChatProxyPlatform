#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Phase 1: WireGuard Hub Diagnostics via AWS CLI
    
.DESCRIPTION
    Checks AWS EC2 instance health, security group, and WireGuard service status
    to diagnose why the VPN hub is not responding.
    
.PARAMETER StartSSM
    If true, opens SSM session to the hub for interactive debugging
    
.EXAMPLE
    .\phase1-wireguard-hub-diagnostics.ps1
    .\phase1-wireguard-hub-diagnostics.ps1 -StartSSM
#>
[CmdletBinding()]
param(
    [switch]$StartSSM
)

$ErrorActionPreference = "Continue"

function Write-OK   { param([string]$msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Fail { param([string]$msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Warn { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Step { param([string]$msg) Write-Host "`n$msg" -ForegroundColor Cyan -BackgroundColor Black }

$instanceId = "i-021b5be52f91cc6fa"
$region = "us-east-1"
$eip = "3.220.226.162"
$vpcId = "vpc-*"  # Will be queried

Write-Host "`n════════════════════════════════════════════════════════════"
Write-Host "  Phase 1: WireGuard Hub Diagnostics (AWS)" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════`n"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.1 Checking AWS CLI"
# ─────────────────────────────────────────────────────────────────────────────

$aws = Get-Command aws.cmd -ErrorAction SilentlyContinue
if (-not $aws) {
    Write-Fail "AWS CLI not found. Install from https://aws.amazon.com/cli/"
    exit 1
}
Write-OK "AWS CLI installed: $(aws --version)"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.2 EC2 Instance Status"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "  Checking instance $instanceId in $region..."
$instance = aws ec2 describe-instances `
    --instance-ids $instanceId `
    --region $region `
    --query 'Reservations[0].Instances[0]' `
    --output json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

if (-not $instance) {
    Write-Fail "Could not retrieve instance $instanceId"
    Write-Host "  Make sure you have AWS credentials configured: aws configure"
    exit 1
}

$state = $instance.State.Name
$publicIp = $instance.PublicIpAddress
$privateIp = $instance.PrivateIpAddress
$sgId = $instance.SecurityGroups[0].GroupId

if ($state -eq "running") {
    Write-OK "Instance state: $state"
} else {
    Write-Fail "Instance state: $state (expected 'running')"
    Write-Host "  >> Try: aws ec2 start-instances --instance-ids $instanceId --region $region"
}

Write-OK "Public IP: $publicIp (EIP: $eip)"
Write-OK "Private IP: $privateIp"
Write-OK "Security Group: $sgId"

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.3 System Status Checks"
# ─────────────────────────────────────────────────────────────────────────────

$statusChecks = aws ec2 describe-instance-status `
    --instance-ids $instanceId `
    --region $region `
    --query 'InstanceStatuses[0]' `
    --output json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($statusChecks) {
    $sysStatus = $statusChecks.SystemStatus.Status
    $instStatus = $statusChecks.InstanceStatus.Status
    
    if ($sysStatus -eq "ok") {
        Write-OK "System Status: $sysStatus"
    } else {
        Write-Fail "System Status: $sysStatus"
    }
    
    if ($instStatus -eq "ok") {
        Write-OK "Instance Status: $instStatus"
    } else {
        Write-Fail "Instance Status: $instStatus"
    }
} else {
    Write-Warn "Status checks not yet available (may take a minute)"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.4 Security Group: WireGuard (UDP 51820)"
# ─────────────────────────────────────────────────────────────────────────────

$sg = aws ec2 describe-security-groups `
    --group-ids $sgId `
    --region $region `
    --output json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

$wgRule = $sg.SecurityGroups[0].IpPermissions | Where-Object { $_.FromPort -eq 51820 }

if ($wgRule) {
    Write-OK "WireGuard UDP 51820 is open: $($wgRule.IpRanges[0].CidrIp)"
} else {
    Write-Fail "WireGuard UDP 51820 is NOT open in security group"
    Write-Host "  >> Fix with Terraform or AWS Console"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.5 Security Group: SSH (TCP 22)"
# ─────────────────────────────────────────────────────────────────────────────

$sshRule = $sg.SecurityGroups[0].IpPermissions | Where-Object { $_.FromPort -eq 22 }

if ($sshRule) {
    Write-OK "SSH TCP 22 is open: $($sshRule.IpRanges[0].CidrIp -join ', ')"
} else {
    Write-Fail "SSH TCP 22 is NOT open in security group"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.6 Network Connectivity Test (from this machine)"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "  Testing UDP 51820 to $eip (this may take 10 seconds)..."
$timeout = 2000
$test = Test-NetConnection -ComputerName $eip -Port 51820 -TraceRoute -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

if ($test.TcpTestSucceeded) {
    Write-OK "Port 51820 reachable"
} else {
    Write-Warn "Port 51820 not responding (expected for UDP - see trace below)"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.7 SSM Session Manager Check"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "  Testing SSM access to $instanceId..."

# Check IAM role
$role = $instance.IamInstanceProfile
if ($role) {
    Write-OK "IAM Role attached: $($role.Arn)"
} else {
    Write-Warn "No IAM role attached (SSM may not work)"
}

# Try to describe the instance via SSM
$ssmCheck = aws ssm describe-instance-information `
    --instance-information-filter-list "key=InstanceIds,valueSet=$instanceId" `
    --region $region `
    --output json 2>&1 | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($ssmCheck.InstanceInformationList.Count -gt 0) {
    Write-OK "SSM Session Manager available"
} else {
    Write-Warn "SSM Session Manager not available (instance may need SSM Agent)"
}

# ─────────────────────────────────────────────────────────────────────────────
Write-Step "1.8 Summary"
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "`n  Instance ID:      $instanceId"
Write-Host "  State:            $state"
Write-Host "  Public IP (EIP):  $eip"
Write-Host "  Security Group:   $sgId"
Write-Host "  Region:           $region"

Write-Host "`n  Next Steps:"
Write-Host "    1. If instance is stopped, start it:"
Write-Host "       aws ec2 start-instances --instance-ids $instanceId --region $region"
Write-Host ""
Write-Host "    2. Check WireGuard service on hub via SSM:"
Write-Host "       aws ssm start-session --target $instanceId --region $region"
Write-Host "       Then: wg show"
Write-Host ""
Write-Host "    3. If connected, proceed to Phase 2: Activate local WireGuard"
Write-Host ""

if ($StartSSM) {
    Write-Host "`n  Opening SSM session to $instanceId..."
    aws ssm start-session --target $instanceId --region $region
}
