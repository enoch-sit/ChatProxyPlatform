# Workstation Deployment Action Plan

**Date:** April 28, 2026  
**Target:** aidcec-demo-windows-workstation (10.10.0.2)  
**Branch:** deploy/localdeploy (commit d90e33c)

## Current State ✓

| Component | Status | Details |
|-----------|--------|---------|
| WireGuard VPN | ✅ ACTIVE | Interface wg-fleet, IP 10.10.0.2/24, connected |
| SSH Service | ✅ RUNNING | Port 22 listening, Automatic startup |
| Git Repo | ✅ READY | Branch: deploy/localdeploy, commit d90e33c |
| Network | ✅ GOOD | Primary IP: 202.45.58.114, VPN routes active |
| Disk Space | ✅ OK | C: 1717 GB free, D: 1890 GB free |

## Blocker 🚨

| Component | Issue | Fix |
|-----------|-------|-----|
| Docker Desktop | ❌ NOT RUNNING | Run `.\start-docker.ps1` on workstation |

## Deployment Steps

### Step 1: Start Docker Desktop (On Workstation)
```powershell
git pull origin deploy/localdeploy
.\start-docker.ps1
```

**Expected:** Docker daemon becomes responsive, `docker ps` returns running containers list.

### Step 2: Verify Readiness (On Workstation)
```powershell
.\check-deployment-readiness.ps1
```

**Expected:** All checks pass with ✓ marks, exit code 0.

### Step 3: Deploy Services (From Management Machine)
```powershell
.\fleet.ps1 -Action patch -Target aidcec-demo-windows-workstation -PatchMode full
```

**Expected:**
- Fleet connects via SSH to 10.10.0.2
- Pulls latest code from deploy/localdeploy
- Rebuilds services with `npm ci` / `pip install`
- Restarts docker-compose with new images
- All 5 services start: auth, accounting, bridge, flowise, flowise-proxy

### Step 4: Validate Deployment (From Management Machine)
```powershell
.\fleet.ps1 -Action health -Target aidcec-demo-windows-workstation
```

**Expected:** Health check passes for all services, endpoints return HTTP 200.

## Known Issues to Watch

1. **JWT_SECRET:** May need to be set in auth-service/.env if not already configured
2. **Missing .env files:** Probe showed missing environment files - create before deployment
3. **Docker startup time:** Docker Desktop can take 30-60 seconds to become ready

## Rollback Plan

If deployment fails:
```powershell
# SSH to workstation and stop services
ssh -i ~/.ssh/fleet_ed25519 fleet@10.10.0.2

# Stop docker-compose
cd ChatProxyPlatform
docker-compose down

# Revert to previous version
git checkout <previous-commit>
docker-compose up -d
```

## Timeline

- **Step 1:** 30-60 seconds (Docker startup)
- **Step 2:** 10 seconds (readiness check)
- **Step 3:** 5-10 minutes (build + deploy)
- **Step 4:** 30 seconds (health check)

**Total:** ~10-15 minutes

---

**Next Action:** Run `.\start-docker.ps1` on the workstation to unblock Docker.
