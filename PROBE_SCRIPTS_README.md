# Workstation State Probe Scripts

Two diagnostic scripts for remote workstation troubleshooting without SSH access.

## Usage

### From Management Machine

1. **Pull the latest scripts:**
   ```powershell
   git pull origin deploy/localdeploy
   ```

2. **On the Remote Workstation** - clone/pull the repo and run:

   **Windows Batch version:**
   ```bat
   probe-workstation-state.bat > workstation-state.log 2>&1
   ```

   **PowerShell version (recommended):**
   ```powershell
   .\probe-workstation-state.ps1 | Tee-Object -FilePath workstation-state.log
   ```

3. **Send output back** - Either:
   - **Copy the log file manually** to management machine
   - **Via SSH** (once SSH is working):
     ```powershell
     scp -i fleet_ed25519 workstation-state.log fleet@10.10.0.3:logs/workstation-state-remote.log
     ```

## Scripts

### probe-workstation-state.bat
- Pure Windows batch script
- No dependencies
- Runs on any Windows version
- Outputs logs to `workstation-state.log`

**Gathers:**
- System info (OS, boot time, version)
- Network config (all interfaces, IPv4/IPv6)
- WireGuard interface status
- SSH service status
- Docker version and containers
- Port listening status
- Process list
- Firewall rules
- Disk space
- Git branch info
- Docker logs (last 30 lines per container)

### probe-workstation-state.ps1
- PowerShell version (more detailed, better formatting)
- Requires PowerShell 5.0+
- Prettier colored output
- Same diagnostics as .bat version plus:
  - Formatted tables and lists
  - Better structured output
  - Process details (CPU, memory)
  - Volume details (free space)

**Gathers:**
- All items from .bat version
- Plus formatted process info (CPU, memory)
- Plus disk volume details
- Plus route table

## What to Look For

### WireGuard Status
```
✓ Should show active interface
✓ Should show peer endpoint: 3.220.226.162:51820
✓ Should show VPN IP: 10.10.0.2/24
✗ If no interface, WireGuard not active
```

### SSH Service
```
✓ Status should be "Running"
✓ StartType should be "Automatic" or "Manual"
✗ If Stopped, service needs to be started:
    net start sshd
```

### Docker Containers
```
✓ Should list: auth-service, accounting-service, bridge, flowise, flowise-proxy, etc.
✓ Status should show "Up" for running containers
✗ If no containers, docker-compose might not have run
```

### Listening Ports
```
✓ Port 22 (SSH) - should be listening if SSH is running
✓ Port 3000 (auth-service)
✓ Port 3001 (accounting-service)
✓ Port 3082 (bridge UI)
✓ Port 3002 (flowise)
✓ Port 8000 (flowise-proxy)
```

### Firewall Rules
```
✓ Should have "SSH Server (sshd)" rule with "Allow" action
✗ If no SSH rule, add one:
    New-NetFirewallRule -Name "SSH" -DisplayName "SSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

## Troubleshooting Steps

If workstation appears offline:

1. **Run PowerShell version:**
   ```powershell
   .\probe-workstation-state.ps1 | Tee-Object workstation-state.log
   ```

2. **Check SSH service:**
   - Look for: `Status: Running` or `Stopped`
   - If stopped, start it: `Start-Service sshd`

3. **Check firewall:**
   - Look for SSH port 22 in listening ports
   - If not there, create firewall rule for SSH

4. **Check WireGuard:**
   - Look for active interface with VPN IP 10.10.0.2
   - If missing, activate: `wg-quick up wg-fleet.conf`

5. **Check Docker:**
   - Look for containers in status output
   - If none, run: `docker-compose up -d`

6. **Send the log back** to management machine for analysis

## Files Created

- `probe-workstation-state.bat` - Batch diagnostic script
- `probe-workstation-state.ps1` - PowerShell diagnostic script
- `PROBE_SCRIPTS_README.md` - This file

## Deployment Helper Scripts

After diagnostics are complete, use these scripts to prepare for deployment:

### check-deployment-readiness.ps1
Verifies all prerequisites before deployment:
```powershell
.\check-deployment-readiness.ps1
```

Checks:
- SSH service running and listening on port 22
- Docker daemon responsive
- WireGuard VPN active (10.10.0.2)
- Git branch on deploy/localdeploy
- Environment files (.env) present
- Disk space available

**Output:** Shows ✓/✗ for each check. Exit code 0 = ready, 1 = not ready.

### start-docker.ps1
Starts Docker Desktop and waits for it to be ready:
```powershell
.\start-docker.ps1
```

If Docker is offline after running diagnostics:
1. **On workstation:** Pull latest and run:
   ```powershell
   git pull origin deploy/localdeploy
   .\start-docker.ps1
   ```

2. **Verify readiness:**
   ```powershell
   .\check-deployment-readiness.ps1
   ```

3. **From management machine, deploy:**
   ```powershell
   .\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode full
   ```

## Diagnostic Workflow

1. **Run probe on workstation:**
   ```powershell
   .\probe-workstation-state.ps1 | Tee-Object workstation-state.log
   ```

2. **Share output with management machine** (manual copy, scp, etc.)

3. **Analyze for blockers:**
   - ✓ SSH running + listening? → Can SSH now
   - ✗ Docker not running? → Run `.\start-docker.ps1`
   - ✓ WireGuard active? → VPN tunnel OK
   - ✗ Missing .env files? → Create them before deployment

4. **Check readiness:**
   ```powershell
   .\check-deployment-readiness.ps1
   ```

5. **If ready, deploy:**
   ```powershell
   # From management machine:
   .\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode full
   ```

## Git Commits

```
d90e33c fix: probe-workstation-state.ps1 - replace Unicode chars with ASCII
8d46b15 add: deployment helper scripts (start-docker, check-deployment-readiness)
7af9895 add: PROBE_SCRIPTS_README.md with usage guide
a82d526 add: probe-workstation-state.ps1 (PowerShell version)
f8785a3 add: probe-workstation-state.bat for remote diagnostics
```

Branch: `deploy/localdeploy`
