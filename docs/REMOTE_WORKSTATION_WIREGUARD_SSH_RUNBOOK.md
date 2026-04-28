# Remote Windows Workstation Runbook

> How to inspect, debug, and control a Windows workstation over the ChatProxy WireGuard fleet network using SSH.

## Purpose

Use this runbook when a workstation is reachable only through the fleet WireGuard tunnel and you need evidence-based steps for:

- proving whether connectivity is broken at the network, SSH, or application layer
- reading workstation state remotely
- pushing and running probe scripts through Git
- understanding what can and cannot be controlled headlessly

This runbook is based on commands that were actually executed successfully against `aidcec-demo-windows-workstation` on `2026-04-28`.

## Topology Used

- Hub: `10.10.0.1`
- Management machine: `10.10.0.3`
- Target workstation: `10.10.0.2`
- SSH user: `fleet`
- SSH key: `%USERPROFILE%\.ssh\fleet_ed25519`
- Repo on workstation: `C:\Users\aidcec\Documents\ChatProxyPlatform`
- Branch used during validation: `deploy/localdeploy`

## What Was Proven

The following were directly validated in-session.

| Area | Command or action | Result |
| --- | --- | --- |
| Hub reachability | `ping 10.10.0.1` | Success |
| Workstation reachability | `ping 10.10.0.2` | Success |
| SSH port | `Test-NetConnection -ComputerName 10.10.0.2 -Port 22` | `TcpTestSucceeded = True` |
| SSH login | `ssh fleet@10.10.0.2 "hostname; whoami"` | Returned `DESKTOP-AF69OPD` and `desktop-af69opd\fleet` |
| Git control | remote `git fetch`, `git checkout`, `git pull` | Success |
| Probe execution | remote PowerShell script run over SSH | Success |
| Hub-side remediation | AWS SSM edit of `/etc/wireguard/wg0.conf` and `wg syncconf` | Success |
| Docker backend service | `Start-Service com.docker.service` from remote probe | Success |
| Docker Desktop daemon headless start | launched remotely without logged-in desktop session | Not successful |

## Hard Limitation Proven By Test

Docker Desktop on Windows is not reliably controllable from a pure SSH session when no interactive desktop session exists.

Evidence:

- `query session` over SSH returned `No session exists for *`
- `com.docker.service` started successfully
- `Docker Desktop.exe` was found and launch was issued successfully
- `\\.\pipe\docker_engine` never appeared
- `docker version` and `docker info` continued to fail because the daemon was not reachable

Interpretation:

- Network and SSH were working.
- The blocker was not WireGuard.
- The blocker was not the SSH key.
- The blocker was the absence of an interactive Windows user session for Docker Desktop.

## Connectivity Ladder

Use this exact order. Do not jump to application debugging until each lower layer is proven.

### 1. Verify WireGuard path to the hub

```powershell
ping -n 2 10.10.0.1
```

Expected:

- replies from `10.10.0.1`

If this fails, do not troubleshoot the workstation yet. The management machine is not reaching the fleet hub.

### 2. Verify WireGuard path to the workstation

```powershell
ping -n 4 10.10.0.2
```

Expected:

- replies from `10.10.0.2`

If hub ping works but workstation ping fails, suspect a hub peer mapping issue or workstation WireGuard state.

### 3. Verify TCP/22 before using SSH

```powershell
Test-NetConnection -ComputerName 10.10.0.2 -Port 22 -WarningAction SilentlyContinue
```

Expected:

- `TcpTestSucceeded : True`

If ping works but TCP/22 fails, the likely causes are:

- `sshd` not running
- Windows firewall blocking inbound SSH
- workstation reachable but OpenSSH not healthy

### 4. Prove interactive command execution over SSH

```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 -o ConnectTimeout=15 -o StrictHostKeyChecking=no fleet@10.10.0.2 "hostname; whoami"
```

Expected:

- hostname of target workstation
- user identity for the SSH session

This separates SSH transport failures from later PowerShell quoting or script issues.

## Remote State Inspection Commands

Once SSH works, use small commands first.

### Basic machine identity

```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 "hostname; whoami"
```

### Repository branch and pending state

```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 "cd C:\Users\aidcec\Documents\ChatProxyPlatform; git status --short; git rev-parse --abbrev-ref HEAD"
```

### Docker CLI reachability

```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 "docker version"
```

Interpretation:

- If client version prints and server connection fails, the Docker CLI is installed but the daemon is down.

### Interactive session check

```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 fleet@10.10.0.2 "query session"
```

Interpretation:

- If this returns session rows, a desktop session exists.
- If this returns `No session exists for *`, the box currently has no logged-in desktop session.

That check matters before spending time trying to start Docker Desktop remotely.

## Proven Remote Control Workflow

When quoting gets messy, do not keep escalating inline SSH commands. Push a probe script, pull it on the workstation, then execute it.

That is the workflow that worked reliably in this session.

### Step 1. Make the probe local-first

Create or update a PowerShell probe in the repo with:

- ASCII-only output
- explicit paths
- conservative error handling
- logging that explains what the probe checked

Reason:

- inline PowerShell quoting over SSH was fragile
- Unicode characters in scripts caused parser issues on the remote Windows host under default encoding

The specific issue proven here was a Unicode checkmark in `start-docker.ps1`, which had to be replaced with ASCII before remote execution was reliable.

### Step 2. Commit and push only the probe-related files

Example used successfully:

```powershell
git add start-docker.ps1 probe-docker-state.ps1
git commit -m "fix(start-docker): replace Unicode checkmark with ASCII; add probe-docker-state.ps1"
git push origin deploy/localdeploy
```

### Step 3. Pull the branch on the workstation

```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 -o ConnectTimeout=15 fleet@10.10.0.2 "cd C:\Users\aidcec\Documents\ChatProxyPlatform; git fetch origin; git checkout deploy/localdeploy; git pull origin deploy/localdeploy"
```

What happened in validation:

- the workstation fast-forwarded successfully
- the new probe script became available immediately

### Step 4. Execute the probe remotely

```powershell
ssh -i $env:USERPROFILE\.ssh\fleet_ed25519 -o ConnectTimeout=15 fleet@10.10.0.2 "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\aidcec\Documents\ChatProxyPlatform\probe-docker-state.ps1"
```

This worked and produced useful remote state, including:

- whether Docker Desktop process existed
- whether `com.docker.backend` existed
- whether `com.docker.service` existed and could be started
- whether `\\.\pipe\docker_engine` existed
- whether Docker Desktop executable paths were present
- whether the daemon became reachable

## When the Workstation Stops Responding Over WireGuard

If SSH worked previously and then all workstation traffic fails, test the hub configuration before assuming the workstation is broken.

### Proven symptom pattern

This exact pattern occurred in-session:

- management machine WireGuard interface was up
- workstation traffic failed
- hub had a stale management peer public key bound to `10.10.0.3/32`
- the current management key existed on the hub with `AllowedIPs = (none)`

Effect:

- the hub could not route traffic back to the management machine
- all workstation communication appeared dead even though WireGuard itself looked partially alive

### Proven recovery path

Hub repair was completed through AWS SSM, not Terraform.

Reason:

- the peer list is operationally maintained via SSM
- Terraform peer changes were intentionally not the mechanism used in this environment

What was changed on the hub:

- removed stale management peer key
- added or corrected `AllowedIPs = 10.10.0.3/32` for the current management key
- reloaded config with `wg syncconf`

### Hub validation command

Run on the hub through SSM or direct shell access:

```bash
wg show wg0
```

What to check:

- management peer public key matches the current machine
- management peer has `allowed ips: 10.10.0.3/32`
- workstation peer has `allowed ips: 10.10.0.2/32`
- recent handshakes exist for both peers

Only after that should you retry `ping`, `Test-NetConnection`, and `ssh` from the management machine.

## What You Can Control Reliably Over This Method

The following worked or are structurally supported by the validated path:

- read workstation identity
- read Git branch and pull a branch
- run PowerShell scripts non-interactively
- start Windows services such as `com.docker.service`
- run repo-local health probes
- trigger fleet-managed actions after SSH connectivity is restored

Examples:

```powershell
.\fleet.ps1 -Action health -Target aidcec-demo-windows-workstation
.\fleet.ps1 -Action status -Target aidcec-demo-windows-workstation
.\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode full
```

Use fleet actions only after the lower-level connectivity ladder is green.

## What You Cannot Assume Will Work Headlessly

These require extra care or an interactive desktop session.

- Docker Desktop GUI startup
- anything dependent on the logged-in Windows shell session
- commands whose success depends on a user desktop rather than a service context

If `query session` shows no desktop session, do not keep retrying GUI app launches over SSH.

Prefer one of these recovery paths:

1. Log in physically or via RDP once and start Docker Desktop.
2. Enable Docker Desktop auto-start for a persistent logged-in user session.
3. Move the workstation to a headless-friendly container runtime model if unattended operation is required.

## Common Failure Modes And Their Meaning

| Symptom | Likely layer | What to do next |
| --- | --- | --- |
| `ping 10.10.0.1` fails | management to hub | inspect local WireGuard state first |
| hub ping works, workstation ping fails | hub routing or workstation peer | inspect hub `wg0` peer config |
| ping works, port 22 fails | Windows SSH or firewall | inspect `sshd` and firewall on workstation |
| SSH works, inline PowerShell fails strangely | quoting or encoding | push a probe script through Git instead |
| script parser errors around symbols | file encoding or non-ASCII chars | replace non-ASCII output with ASCII |
| Docker service starts but daemon never appears | desktop session dependency | check `query session` |

## Recommended Operating Pattern

For this environment, use the following control loop.

1. Prove hub connectivity.
2. Prove workstation connectivity.
3. Prove TCP/22.
4. Prove simple SSH command execution.
5. Run a narrow probe script from the repo.
6. If a probe needs edits, commit and push only the probe change.
7. Pull on the workstation and rerun the probe.
8. Use `fleet.ps1` only after the tunnel and SSH path are known-good.

This keeps diagnosis evidence-based and prevents mixing network, shell quoting, and application runtime problems into one step.

## Session Artifacts Produced During Validation

These repo files were created or updated as part of the validated workflow:

- `start-docker.ps1` updated to remove non-ASCII output that broke remote parsing
- `probe-docker-state.ps1` added as a remote Docker state probe

Those changes were pulled successfully on the workstation and the probe executed successfully over the WireGuard SSH path.
