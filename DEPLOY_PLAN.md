# WireGuard Fix & Deployment Plan
**Date**: 2026-04-28  
**Target**: aidcec-demo-windows-workstation (10.10.0.2)  
**Public Key**: leZtpHFhPMLf0F2Q28a7nxoIPlx/nGb2d5AZp+b4hgM=  
**Hub**: AWS EC2 (3.220.226.162:51820, i-021b5be52f91cc6fa)

---

## Phase 1: WireGuard Hub Diagnostics (AWS CLI)

**Goal**: Verify AWS hub is healthy and operational

### 1.1 AWS EC2 Instance Status
```powershell
# Check instance is running
aws ec2 describe-instances --instance-ids i-021b5be52f91cc6fa --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress]'

# Expected: running, EIP 3.220.226.162
```

### 1.2 Security Group Status
```powershell
# Verify security group allows WireGuard UDP 51820 and SSH 22
aws ec2 describe-security-groups --group-ids sg-* \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`51820` || FromPort==`22`]'

# Expected: Inbound UDP 51820 (0.0.0.0/0), Inbound TCP 22 (10.10.0.0/24)
```

### 1.3 EC2 System Status
```powershell
# Check system and instance status checks
aws ec2 describe-instance-status --instance-ids i-021b5be52f91cc6fa

# Expected: StatusChecksFailed=0, SystemStatusChecksFailed=0, InstanceStatusChecksFailed=0
```

### 1.4 SSM Session Check (admin access)
```powershell
# Verify you can reach the hub via SSM (no VPN needed)
aws ssm start-session --target i-021b5be52f91cc6fa

# Inside SSM session:
#   wg show           # List WireGuard interfaces
#   systemctl status wg-quick@wg0
#   ip link show wg0
#   ip address show
```

---

## Phase 2: WireGuard Local Client Fix

**Goal**: Activate WireGuard on this machine

### 2.1 WireGuard Service Status
```powershell
# Check installed
Get-Command wg.exe
Get-Service | Where-Object {$_.Name -like '*wireguard*' -or $_.Name -like '*wg*'}

# If not installed: Download from https://www.wireguard.com/install/
```

### 2.2 Check Active Interfaces
```powershell
# List all WireGuard interfaces
wg show

# If error "Permission denied": run PowerShell as Administrator
# If error "interface not found": interfaces may not be active
```

### 2.3 Activate WireGuard Interface
```powershell
# Windows: Use WireGuard GUI or wg-quick
# Power shell As Admin:
wg-quick up 'c:\ProgramData\WireGuard\Configs\wg-fleet.conf'

# Or via GUI: WireGuard app → Import → wg-fleet.conf → Activate
```

### 2.4 Verify Local Interface
```powershell
# Check interface is active and has IP 10.10.0.3
wg show wg-fleet
ipconfig /all | Select-String "10.10.0"

# Expected:
#   Interface: 10.10.0.3/24
#   Peer public key: cUDvoyHcJs7T3mpfQYA0xJ130/ff4udsNBchH+/l7T0=
#   Endpoint: 3.220.226.162:51820
```

---

## Phase 3: Connectivity Test

**Goal**: Verify VPN tunnel is working

### 3.1 Ping Hub
```powershell
ping 10.10.0.1  # Should succeed, reply from hub

# If timeout:
#   - Check WireGuard is active (Phase 2.3)
#   - Check firewall allows UDP 51820
#   - Verify AWS security group (Phase 1.2)
```

### 3.2 Ping Workstation
```powershell
ping 10.10.0.2  # Should succeed, reply from workstation

# If timeout:
#   - Workstation may be powered off
#   - Workstation WireGuard may not be active
#   - See Phase 4 for remote diagnostics
```

### 3.3 SSH to Hub (via VPN)
```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 ec2-user@10.10.0.1 "uname -a"

# Expected: Amazon Linux 2023
# If connection timeout:
#   - Check Phase 2.4 (local WireGuard active)
#   - Check Phase 1.2 (SSH port in security group)
```

---

## Phase 4: Remote Workstation Diagnostics (via SSH relay)

**Goal**: Check workstation state from hub

### 4.1 SSH to Workstation (through hub)
```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 "Get-ComputerInfo" 2>&1

# Expected: Windows version, network config
# If connection timeout:
#   - Workstation offline or WireGuard not configured
#   - See Phase 4.4 for remote setup
```

### 4.2 Check Workstation Services
```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 @"
  Get-Service docker | Select-Object Name, Status
  docker ps
"@

# Expected: Docker running, containers present
```

### 4.3 Check WireGuard on Workstation
```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 @"
  ipconfig | Select-String "10.10.0"
  route print | Select-String "10.10.0"
"@

# Expected: WireGuard IP 10.10.0.2/24
```

### 4.4 If Workstation Not Responding
```powershell
# Power on via AWS if it's an EC2 instance, OR
# Use WireGuard onboarding script on workstation machine:

# (On workstation directly):
.\wg-workstation-setup.ps1 `
  -HubEndpoint "3.220.226.162:51820" `
  -HubPublicKey "cUDvoyHcJs7T3mpfQYA0xJ130/ff4udsNBchH+/l7T0=" `
  -MyIP "10.10.0.2/24"
```

---

## Phase 5: Machine State Probe

**Goal**: Full diagnostics of both local and remote

### 5.1 Local Machine Probe
```powershell
.\diagnose.ps1 -Full

# Outputs:
#   - Prerequisites (docker, node, python, git)
#   - Docker daemon & containers
#   - Service health endpoints
#   - Port availability
#   - .env files
#   - JWT secret sync
```

### 5.2 Remote Workstation Probe
```powershell
.\fleet.ps1 -Action health -Target aidcec-demo-windows-workstation

# Outputs:
#   - Remote diagnostics via SSH
#   - Container status
#   - Disk space
#   - Network routes
#   - Service versions
```

### 5.3 Peer State Probe
```powershell
# From local machine:
wg show wg-fleet peers

# From hub (via SSH):
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 ec2-user@10.10.0.1 wg show wg0 peers

# Expected: Lists all peers (10.10.0.2, 10.10.0.3, etc.) with handshake times
```

---

## Phase 6: Patch & Debug (on target workstation)

**Goal**: Apply changes and prepare for deployment

### 6.1 Patch Workstation
```powershell
.\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode quick

# Outputs:
#   - Pulls latest code
#   - Runs rebuild.bat on changed services
#   - Restarts containers
```

### 6.2 Remote Debug
```powershell
# Run remote diagnostics
.\fleet.ps1 -Action health -Target aidcec-demo-windows-workstation

# Check specific service logs
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 `
  "docker logs auth-service --tail 50"

# Verify JWT_SECRET is set
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 `
  "docker exec auth-service env | Select-String JWT"
```

### 6.3 Health Check
```powershell
# Test all service endpoints from workstation
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 @"
  curl.exe -s http://localhost:3000/health         # auth-service
  curl.exe -s http://localhost:3001/health         # accounting-service
  curl.exe -s http://localhost:8000/health         # flowise-proxy
  curl.exe -s http://localhost:3082/               # bridge
  curl.exe -s http://localhost:3002/api/v1/ping    # flowise
"@

# Expected: HTTP 200 for all
```

---

## Phase 7: Deploy (deploy/localdeploy → workstation)

**Goal**: Full deployment to target

### 7.1 Verify Branch
```powershell
git branch --show-current           # Should be deploy/localdeploy
git diff HEAD MERGE_BASE(main)      # Check what will deploy
```

### 7.2 Deploy Workflow
```powershell
.\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode full

# This runs:
#   1. git pull origin deploy/localdeploy
#   2. npm ci / pip install (dependencies)
#   3. rebuild.bat (compile/build each service)
#   4. docker-compose up -d (restart services)
```

### 7.3 Post-Deployment Validation
```powershell
# Health check
.\fleet.ps1 -Action health -Target aidcec-demo-windows-workstation

# Test chatflow endpoint
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 @"
  curl.exe -s http://localhost:3082/ -w "`nHTTP %{http_code}`n"
"@

# Monitor logs
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 `
  "docker logs -f bridge --tail 20"
```

---

## Troubleshooting Checklist

| Issue | Cause | Fix |
|-------|-------|-----|
| WireGuard "interface not found" | Not installed or activated | Phase 2.2 → Install / Phase 2.3 → Activate |
| `ping 10.10.0.1` timeout | Local WireGuard not active | Phase 2.3 + Phase 2.4 |
| `ssh 10.10.0.1` timeout | Hub unreachable or no route | Phase 1.1 + Phase 1.2 (AWS) |
| `ssh 10.10.0.2` timeout | Workstation offline or no WireGuard | Phase 4.3 + Phase 4.4 |
| Deployment fails after SSH | Incompatible PowerShell version | Use PowerShell 7+ (`pwsh`) |
| Services crash on workstation | .env missing or JWT_SECRET not set | Phase 6.2 (verify env vars) |
| Hub can't route traffic | Peer not registered or peer not active | Phase 5.3 (check peer list) |

---

## Execution Order

```
Phase 1: AWS CLI Diagnostics (10 min)
  ↓
Phase 2: Local WireGuard Activation (5 min)
  ↓
Phase 3: Connectivity Test (5 min)
  ↓
Phase 4: Remote Workstation Check (10 min)
  ↓
Phase 5: Machine & Peer State Probe (10 min)
  ↓
Phase 6: Patch & Debug (15 min)
  ↓
Phase 7: Deploy (10 min)
  ↓
✅ DONE
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `wg-fleet.conf` | Local WireGuard config (10.10.0.3/24) |
| `fleet.ps1` | Fleet management (status, patch, health) |
| `diagnose.ps1` | Local diagnostics |
| `patch.ps1` | Pull & rebuild on workstation |
| `infra/modules/wireguard/` | AWS hub Terraform |
| `fleet-inventory.json` | Hub + workstations registry |
| `~/.ssh/fleet_ed25519` | SSH key for fleet access |

---

## Commands Quick Reference

```powershell
# Activate WireGuard
wg-quick up 'c:\ProgramData\WireGuard\Configs\wg-fleet.conf'

# Test connectivity
ping 10.10.0.1
ping 10.10.0.2

# SSH to hub
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 ec2-user@10.10.0.1

# SSH to workstation
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2

# Fleet status
.\fleet.ps1 -Action status

# Fleet patch
.\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode quick

# Local diagnostics
.\diagnose.ps1 -Full

# Remote diagnostics
.\fleet.ps1 -Action health -Target aidcec-demo-windows-workstation
```
