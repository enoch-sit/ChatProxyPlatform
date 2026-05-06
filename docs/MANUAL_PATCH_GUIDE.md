# Manual Patch Guide — ChatProxy Platform

> How to update services on a Windows workstation **without** using `fleet.ps1`.
>
> Branch note: do not follow old `main`-based patching habits. Use `bhss` for the live Windows production line and `test/localdeploy` for development workstations unless you intentionally need another branch for investigation.

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Prerequisites](#prerequisites)
3. [Deployment Order](#deployment-order)
4. [Standard Manual Patch (All Services)](#standard-manual-patch-all-services)
5. [Patch a Single Service](#patch-a-single-service)
6. [Service-by-Service Reference](#service-by-service-reference)
7. [Using patch.ps1 Locally](#using-patchps1-locally)
8. [Health Checks & Verification](#health-checks--verification)
9. [Rollback](#rollback)
10. [Environment Variable Sync](#environment-variable-sync)
11. [Troubleshooting](#troubleshooting)

---

## Quick Reference

```powershell
# Minimal manual patch — run from the repo root on the workstation
cd C:\chatproxy          # or wherever the repo is cloned
git pull origin bhss      # use test/localdeploy on non-production workstations
.\auth-service\rebuild.bat
.\accounting-service\rebuild.bat
.\flowise\start.bat
.\flowise-proxy-service-py\rebuild-docker.bat
.\bridge\rebuild.bat
```

That's it. The sections below explain *why* and *when* to deviate.

---

## Prerequisites

| Requirement       | Minimum Version | Check Command                   |
|-------------------|-----------------|---------------------------------|
| Docker Desktop    | 4.x+            | `docker --version`              |
| Docker Compose    | v2.x            | `docker compose version`        |
| Git               | 2.x             | `git --version`                 |
| Node.js           | 18.x            | `node --version`                |
| Python            | 3.11+           | `python --version`              |
| PowerShell        | 5.1+            | `$PSVersionTable.PSVersion`     |

Docker Desktop **must** be running before any service commands. Verify:

```powershell
docker info | Select-String "Server Version"
```

If Docker is not running, start Docker Desktop from the Start Menu and wait for it to initialize.

---

## Deployment Order

Services **must** be deployed in this order (defined in `workstation-manifest.json`):

| Order | Service              | Port  | Health Endpoint     | Compose File            |
|-------|----------------------|-------|---------------------|-------------------------|
| 1     | auth-service         | 3000  | `/health`           | `docker-compose.dev.yml`|
| 2     | accounting-service   | 3001  | `/health`           | `docker-compose.yml`    |
| 3     | flowise              | 3002  | `/api/v1/ping`      | `docker-compose.yml`    |
| 4     | flowise-proxy        | 8000  | `/health`           | `docker-compose.yml`    |
| 5     | bridge               | 3082  | `/`                 | `docker-compose.yml`    |

**Why order matters:**
- `auth-service` issues JWTs — everything else depends on it
- `accounting-service` validates credits — proxy needs it
- `flowise` must be running before `flowise-proxy` can forward requests
- `bridge` is the UI and connects to `flowise-proxy`

---

## Standard Manual Patch (All Services)

### Step 1 — Pull Latest Code

```powershell
cd C:\chatproxy
git pull origin bhss      # use test/localdeploy on non-production workstations
```

If you have local changes that conflict:

```powershell
git stash
git pull origin bhss      # use test/localdeploy on non-production workstations
git stash pop       # re-apply your local changes
```

### Step 2 — Rebuild & Restart Each Service (In Order)

#### 2a. Auth Service

```powershell
cd auth-service
.\rebuild.bat
cd ..
```

What `rebuild.bat` does:
- `docker compose -f docker-compose.dev.yml down`
- `docker compose -f docker-compose.dev.yml build --no-cache`
- `docker compose -f docker-compose.dev.yml up -d`

Containers started: `auth-service`, `mongodb`, `mailhog`

Verify:
```powershell
curl http://localhost:3000/health
```

#### 2b. Accounting Service

```powershell
cd accounting-service
.\rebuild.bat
cd ..
```

What `rebuild.bat` does:
- `docker compose down`
- `docker compose build --no-cache`
- `docker compose up -d`

Containers started: `accounting-service`, `postgres-accounting`

Verify:
```powershell
curl http://localhost:3001/health
```

#### 2c. Flowise

```powershell
cd flowise
.\start.bat
cd ..
```

> **Note:** Flowise uses a prebuilt image (`flowiseai/flowise`), so `start.bat` (`docker compose up -d`) is usually sufficient. Only rebuild if you changed the compose config or `.env`.

Containers started: `flowise`, `flowise-postgres`

Verify:
```powershell
curl http://localhost:3002/api/v1/ping
```

#### 2d. Flowise Proxy

```powershell
cd flowise-proxy-service-py
.\rebuild-docker.bat
cd ..
```

What `rebuild-docker.bat` does:
- `docker-compose down -v` (removes volumes for clean state)
- `docker image prune -f` (removes dangling images)
- `docker-compose up --build -d`
- Shows container status and last 20 log lines

Containers started: `flowise-proxy`, `mongodb-proxy`

Verify:
```powershell
curl http://localhost:8000/health
```

> **Warning:** `rebuild-docker.bat` uses `-v` which removes proxy MongoDB data. If you only want a code update without losing data, run manually:
> ```powershell
> docker compose down
> docker compose up --build -d
> ```

#### 2e. Bridge (UI)

```powershell
cd bridge
.\rebuild.bat
cd ..
```

What `rebuild.bat` does:
- `docker compose down`
- `docker compose up -d --build --force-recreate`

Container started: `bridge-ui`

Verify:
```powershell
curl http://localhost:3082/
```

### Step 3 — Run Health Checks

```powershell
.\diagnose.ps1 -Quick
```

This validates Docker, all containers, and all health endpoints in one command.

---

## Patch a Single Service

If you know only one service changed, you can patch just that service:

```powershell
cd C:\chatproxy
git pull origin bhss      # use test/localdeploy on non-production workstations

# Example: only auth-service changed
cd auth-service
.\rebuild.bat
```

**Quick patch** (config/env change only — no code change):
```powershell
cd auth-service
.\stop.bat
.\start.bat
```

This skips the image rebuild and just restarts the containers, which is faster.

**Full rebuild** (code or Dockerfile changed):
```powershell
cd auth-service
.\rebuild.bat
```

---

## Service-by-Service Reference

### auth-service

| Script        | Purpose                                      |
|---------------|----------------------------------------------|
| `rebuild.bat` | Full stop → build --no-cache → start         |
| `start.bat`   | Start containers (checks if already running) |
| `stop.bat`    | Stop containers (`-v` to also remove volumes)|
| `logs.bat`    | Tail logs: `docker logs auth-service -f`     |

- Compose file: `docker-compose.dev.yml`
- Ports: 3000 (API), 27017 (MongoDB), 8025 (MailHog UI)
- Containers: `auth-service`, `mongodb`, `mailhog`

### accounting-service

| Script        | Purpose                                      |
|---------------|----------------------------------------------|
| `rebuild.bat` | Full stop → build --no-cache → start         |
| `start.bat`   | Start containers (checks if already running) |
| `stop.bat`    | Stop containers                              |
| `logs.bat`    | Tail logs: `docker logs accounting-service -f`|

- Compose file: `docker-compose.yml`
- Ports: 3001 (API), 5432 (PostgreSQL)
- Containers: `accounting-service`, `postgres-accounting`

### flowise

| Script                   | Purpose                                      |
|--------------------------|----------------------------------------------|
| `start.bat`              | Start containers                             |
| `stop.bat`               | Stop containers                              |
| `start-with-postgres.bat`| Start with explicit .env loading             |
| `debug.bat`              | Collect diagnostics to timestamped log file  |

- Compose file: `docker-compose.yml`
- Ports: 3002 (Flowise UI/API), 5433 (PostgreSQL)
- Containers: `flowise`, `flowise-postgres`
- No `rebuild.bat` — uses prebuilt image from Docker Hub

### flowise-proxy-service-py

| Script              | Purpose                                             |
|---------------------|-----------------------------------------------------|
| `rebuild-docker.bat`| Full teardown (with volumes) → prune → rebuild      |
| `start-docker.bat`  | Start containers                                    |
| `start.bat`         | Local dev (Python venv, not Docker)                  |
| `stop.bat`          | Stop containers                                     |
| `logs.bat`          | Tail compose logs                                   |

- Compose file: `docker-compose.yml`
- Ports: 8000 (API), 27020 (MongoDB internal)
- Containers: `flowise-proxy`, `mongodb-proxy`

### bridge

| Script        | Purpose                                      |
|---------------|----------------------------------------------|
| `rebuild.bat` | Stop → build + force-recreate → start        |
| `start.bat`   | Build and start                              |
| `stop.bat`    | Stop containers                              |
| `logs.bat`    | Tail: `docker compose logs -f bridge-ui`     |

- Compose file: `docker-compose.yml`
- Ports: 3082 (UI)
- Container: `bridge-ui`

---

## Using patch.ps1 Locally

Instead of running individual `rebuild.bat` files, you can use `patch.ps1` from the repo root. This automates detection, ordering, and health checks.

### Modes

| Mode     | When to Use                                   | What It Does                              |
|----------|-----------------------------------------------|-------------------------------------------|
| `auto`   | Default — let it decide                       | Detects what changed, picks quick or full  |
| `quick`  | Only `.env` or config files changed           | `git pull` → `docker compose up -d`       |
| `full`   | Code or Dockerfile changed                    | `git pull` → test → `docker compose up -d --build` |
| `test`   | Run tests without deploying                   | `git pull` → `npm test` / `pytest`        |
| `status` | Check what would change                       | Shows version diff, changed services      |

### Examples

```powershell
# Auto-detect and patch everything
.\patch.ps1

# Full rebuild of all services
.\patch.ps1 -Mode full -Force

# Quick restart of a single service
.\patch.ps1 -Mode quick -Service auth-service

# See what changed without deploying
.\patch.ps1 -Mode status

# Roll back to previous version
.\patch.ps1 -Rollback
```

### What patch.ps1 Does Internally

1. Checks Docker is running
2. Runs `git pull`
3. Compares `version.json` vs `.local-version` to detect changes
4. Rebuilds only changed services (unless `-Force`)
5. Follows deploy order from `workstation-manifest.json`
6. Health-checks each service after restart (8 retries, 3s apart)
7. Updates `.local-version` on success
8. Writes a log to `logs/`

---

## Health Checks & Verification

### Quick Check (All Services)

```powershell
.\diagnose.ps1 -Quick
```

### Manual Health Checks

```powershell
# Auth
curl http://localhost:3000/health

# Accounting
curl http://localhost:3001/health

# Flowise
curl http://localhost:3002/api/v1/ping

# Flowise Proxy
curl http://localhost:8000/health

# Bridge
curl http://localhost:3082/
```

### Container Status

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected containers (6 services + supporting databases):

| Container              | Image                          |
|------------------------|--------------------------------|
| auth-service           | Local build                    |
| mongodb                | mongo:6.0                      |
| mailhog                | mailhog/mailhog                |
| accounting-service     | Local build                    |
| postgres-accounting    | postgres:14-alpine             |
| flowise                | flowiseai/flowise              |
| flowise-postgres       | postgres:15-alpine             |
| flowise-proxy          | Local build                    |
| mongodb-proxy          | mongo:7-jammy                  |
| bridge-ui              | Local build                    |

### Full Diagnostics (with log file)

```powershell
.\diagnose.ps1 -Full -SaveLog
# Output saved to: logs/diagnose_YYYYMMDD_HHMMSS.log
```

### Login Flow Test

```powershell
.\diagnose.ps1 -Login
```

This tests JWT issuance, CORS headers, auth flow, and MongoDB connectivity.

---

## Rollback

### Using patch.ps1

```powershell
.\patch.ps1 -Rollback
```

This reverts to the previous git state and rebuilds all services.

### Manual Rollback

```powershell
# Find the previous commit
git log --oneline -5

# Revert to a specific commit
git checkout <commit-hash>

# Rebuild everything
.\auth-service\rebuild.bat
.\accounting-service\rebuild.bat
.\flowise\stop.bat && .\flowise\start.bat
.\flowise-proxy-service-py\rebuild-docker.bat
.\bridge\rebuild.bat

# Verify
.\diagnose.ps1 -Quick
```

### Rollback a Single Service

If only one service is broken:

```powershell
# Check which commit last changed this service
git log --oneline -5 -- auth-service/

# Restore the previous version of just that directory
git checkout <commit-hash> -- auth-service/

# Rebuild
cd auth-service
.\rebuild.bat
```

---

## Environment Variable Sync

### Critical: JWT Secrets Must Match

The following variables **must be identical** across three services:

| Variable             | Files                                                               |
|----------------------|---------------------------------------------------------------------|
| `JWT_ACCESS_SECRET`  | `auth-service/.env`, `accounting-service/.env`, `flowise-proxy-service-py/.env` |
| `JWT_REFRESH_SECRET` | `auth-service/.env`, `accounting-service/.env`, `flowise-proxy-service-py/.env` |

If you change JWT secrets, **all three services must be restarted**.

### Generating New Secrets

```powershell
python generate_secrets.py
```

### Checking Secret Sync

```powershell
.\diagnose.ps1 -Login
# This checks JWT_SECRET synchronization across services
```

### Per-Service .env Reference

| Service                   | .env Template         | Key Variables                                             |
|---------------------------|-----------------------|-----------------------------------------------------------|
| auth-service              | `.env.example`        | JWT secrets, MongoDB URI, SMTP, CORS, bcrypt rounds       |
| accounting-service        | `.env.example`        | JWT secrets, PostgreSQL, CORS, credit defaults, rate limit |
| flowise                   | `.env.example`        | Database (Postgres), storage, CORS, upload limits          |
| flowise-proxy-service-py  | `.env.example`        | JWT secrets, Flowise API URL/key, MongoDB, debug settings  |
| bridge                    | `.env.example`        | `VITE_FLOWISE_PROXY_API_URL`                              |

If a `.env` file is missing, copy from `.env.example` and fill in the values:

```powershell
copy auth-service\.env.example auth-service\.env
# Then edit auth-service\.env with actual values
```

---

## Troubleshooting

### Service Won't Start

```powershell
# Check container logs
cd auth-service
.\logs.bat

# Or for any container:
docker logs <container-name> --tail 50
```

### Port Already in Use

```powershell
# Find what's using the port
netstat -ano | findstr :3000

# Kill the process (use the PID from above)
taskkill /PID <pid> /F
```

### Docker Build Fails

```powershell
# Clean Docker cache and retry
docker system prune -f
cd auth-service
.\rebuild.bat
```

### Container Running But Health Check Fails

```powershell
# Check if the app is actually listening
docker exec auth-service curl -s http://localhost:3000/health

# Check container resource usage
docker stats --no-stream
```

### MongoDB Connection Issues

```powershell
# Check MongoDB container
docker logs mongodb --tail 20

# Test connectivity
docker exec mongodb mongosh --eval "db.runCommand({ping: 1})"
```

### "Network chatproxy-network not found"

The shared Docker network must exist. Create it manually:

```powershell
docker network create chatproxy-network
```

### All Services Need Full Reset

Nuclear option — stop everything, clean up, and restart:

```powershell
# Stop all services (in reverse order)
cd bridge && .\stop.bat && cd ..
cd flowise-proxy-service-py && .\stop.bat && cd ..
cd flowise && .\stop.bat && cd ..
cd accounting-service && .\stop.bat && cd ..
cd auth-service && .\stop.bat && cd ..

# Remove all project containers and networks
docker compose -f auth-service/docker-compose.dev.yml down -v
docker compose -f accounting-service/docker-compose.yml down -v
docker compose -f flowise/docker-compose.yml down -v
docker compose -f flowise-proxy-service-py/docker-compose.yml down -v
docker compose -f bridge/docker-compose.yml down -v

# Fresh start
.\setup.ps1
```

> **Warning:** The `-v` flag removes database volumes. You will lose local data (users, chatflows, credits).

---

## Summary: When to Use What

| Scenario                              | Command                                          |
|---------------------------------------|--------------------------------------------------|
| Routine update (all services)         | `git pull` → `.\patch.ps1`                       |
| Single service code change            | `git pull` → `cd <service>` → `.\rebuild.bat`    |
| Config/env change only                | `.\stop.bat` → `.\start.bat`                     |
| Check what would change               | `.\patch.ps1 -Mode status`                       |
| Quick health check                    | `.\diagnose.ps1 -Quick`                          |
| Full diagnostics                      | `.\diagnose.ps1 -Full -SaveLog`                  |
| Something broke, roll back            | `.\patch.ps1 -Rollback`                          |
| Fresh workstation setup               | `.\setup.ps1`                                    |
| Remote patch via fleet                | `.\fleet.ps1 -Action patch -Target <name>`       |
