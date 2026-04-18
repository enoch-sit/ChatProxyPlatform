---
description: "Diagnose fleet connectivity, SSH, or service issues on workstations"
mode: agent
tools:
  - run_in_terminal
  - read_file
---

# Fleet Diagnostics

You are helping diagnose issues with the ChatProxy fleet — WireGuard connectivity, SSH access, or service health problems.

## Diagnostic Ladder

Follow this order. Stop at the first failure and help fix it.

### 1. WireGuard Tunnel
```powershell
# Check local tunnel is up
wg show
# Ping the hub
ping 10.10.0.1 -n 2
# Ping the target workstation
ping <workstation_wireguard_ip> -n 2
```

### 2. SSH Connectivity
```powershell
# Test SSH to workstation (verbose)
ssh -v -i ~/.ssh/fleet_ed25519 -o ConnectTimeout=10 <user>@<wireguard_ip> "echo OK"
```
Common failures:
- **Connection refused**: OpenSSH not running on target → `Get-Service sshd` / `Start-Service sshd`
- **Permission denied**: Key not installed → Run `.\fleet.ps1 -Action deploy-key`
- **Host key verification**: First connection → SSH with `-o StrictHostKeyChecking=accept-new`

### 3. Fleet Status
```powershell
.\fleet.ps1 -Action status
```
Read the output table. OFFLINE = WireGuard issue. SSH_FAIL = key/sshd issue. ONLINE = working.

### 4. Service Health
```powershell
.\fleet.ps1 -Action health -Target <name>
```
Or run diagnose.ps1 locally on the workstation.

### 5. Hub-Side Checks (via SSM)
```powershell
# Check hub WireGuard peers
aws ssm send-command --instance-ids i-021b5be52f91cc6fa --document-name AWS-RunShellScript --parameters 'commands=["wg show"]' --region us-east-1
```

## Reference
- Hub: 10.10.0.1 (EIP 3.220.226.162, instance i-021b5be52f91cc6fa)
- Fleet inventory: `fleet-inventory.json`
- SSH key: `~/.ssh/fleet_ed25519`
