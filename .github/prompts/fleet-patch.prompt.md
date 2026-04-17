---
description: "Patch or deploy updates to fleet workstations"
mode: agent
tools:
  - run_in_terminal
  - read_file
---

# Fleet Patch & Deploy

You are helping patch or deploy updates across the ChatProxy workstation fleet.

## Patch Modes
- **auto** (default): Pull git changes, rebuild only changed services, run smoke tests
- **quick**: Pull + restart containers (no rebuild)
- **full**: Pull + rebuild all services + run full test suite

## Commands

### Patch all workstations
```powershell
.\fleet.ps1 -Action patch -PatchMode auto
```

### Patch a specific workstation
```powershell
.\fleet.ps1 -Action patch -Target <workstation-name> -PatchMode quick
```

### Check status before patching
```powershell
.\fleet.ps1 -Action status
```

### Run health check after patching
```powershell
.\fleet.ps1 -Action health
```

## Full Patch Workflow
1. `.\fleet.ps1 -Action status` — verify workstations are online
2. `.\fleet.ps1 -Action patch -PatchMode auto` — deploy updates
3. `.\fleet.ps1 -Action health` — verify everything is healthy

## If Patching Fails
- Check the output for which workstation/service failed
- Run `.\fleet.ps1 -Action health -Target <name>` for detailed diagnostics
- SSH directly: `.\fleet.ps1 -Action run-command -Target <name> -Command "docker ps"`
- Check logs: `.\fleet.ps1 -Action run-command -Target <name> -Command "docker logs <service> --tail 50"`

## AWS ECS Patching (cloud services)
For cloud-deployed services, use the deploy pipeline instead:
```powershell
# From infra/scripts/
.\deploy-service.ps1 -Service auth-service -Environment dev
```

## Reference
- Workstations: see `fleet-inventory.json`
- Patch logic: `patch.ps1`
- Version tracking: `version.json`
