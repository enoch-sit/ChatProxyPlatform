# Windows Docker Deployment - Complete Setup Guide

Complete step-by-step guide to deploy the ChatProxy Platform on Windows using Docker.

---

## 🚀 Quick Start (Fresh Installation)

**Complete setup in 5 commands:**

```batch
# 1. Clone the repository
git clone https://github.com/enoch-sit/ChatProxyPlatform.git
cd ChatProxyPlatform

# 2. Create .env files from templates
setup_env_files.bat

# 3. Generate secure secrets and passwords
generate_secrets.bat

# 4. Start Flowise with PostgreSQL
cd flowise
start-with-postgres.bat

# 5. Configure Flowise API key (automated)
cd ..
configure_flowise_api.bat
# Opens http://localhost:3002 → Settings → API Keys → Create
# Paste the key when prompted - it auto-updates .env
```

**For existing installations:**
See management commands at the bottom of this guide.

---

## 📋 Prerequisites

- ✅ Docker Desktop installed and running
- ✅ Git (for cloning the repository)
- ✅ Python 3.x installed
- ✅ Windows PowerShell or Command Prompt

**Quick Check:** All setup scripts will verify prerequisites automatically.

---

## 🔧 Step-by-Step Setup

### Step 1: Clone Repository

```batch
git clone https://github.com/enoch-sit/ChatProxyPlatform.git
cd ChatProxyPlatform
```

### Step 2: Create Environment Files

All services require `.env` configuration files (not in git for security).

```batch
setup_env_files.bat
```

**What it does:**
- ✅ Creates `.env` files from templates for all 5 services
- ✅ Skips if files already exist (safe to re-run)
- ✅ Shows summary of created/skipped/errors

**Created files:**
1. `flowise/.env` - Flowise AI + PostgreSQL
2. `auth-service/.env` - Authentication + MongoDB
3. `accounting-service/.env` - Accounting + PostgreSQL
4. `flowise-proxy-service-py/.env` - Proxy + MongoDB
5. `bridge/.env` - Frontend UI

### Step 3: Generate Secrets and Passwords

All JWT secrets and database passwords must be generated securely.

```batch
generate_secrets.bat
```

**What it does:**
- ✅ Generates 64-char secure JWT secrets
- ✅ Generates 32-char database passwords (PostgreSQL & MongoDB)
- ✅ Uses **only shell-safe characters** (alphanumeric + `-`, `_`, `.`)
- ✅ Updates all `.env` files automatically
- ✅ **Same JWT secrets** across auth, accounting, and proxy services
- ✅ Creates `.env.backup` files before updating

**Expected output:**
```
✓ JWT_ACCESS_SECRET: pTeevk7vRzKx... (64 chars)
✓ JWT_REFRESH_SECRET: XTF0aRBtILQL... (64 chars)
✓ POSTGRES_PASSWORD: 67ic_Tao5TpqTMIS... (32 chars)
✓ MONGO_PASSWORD: ATReubut9oP1LQBr... (32 chars)

✓ All 11 updates completed successfully!
```

⚠️ **Note:** `FLOWISE_API_KEY` must be created AFTER Flowise starts (Step 5).

### Step 4: Start Flowise with PostgreSQL

```batch
cd flowise
start-with-postgres.bat
```

**Wait for startup** (30-60 seconds):
```batch
docker ps
```

You should see:
- `flowise` container running
- `flowise-postgres` container running (healthy)

**Access Flowise:**
Open browser: http://localhost:3002

**First-time setup:**
- Create admin account
- Name: `admin`
- Email: `ecysit@eduhk.hk`
- Password: `Admin@2026`

### Step 5: Create Flowise API Key

The proxy service needs an API key to sync chatflows from Flowise.

**Option 1: Automated Configuration (Recommended)**
```batch
configure_flowise_api.bat
```

**What it does:**
1. ✅ Opens instructions for creating Flowise API key
2. ✅ Validates the API key format
3. ✅ Automatically updates `flowise-proxy-service-py/.env`
4. ✅ Creates backup before updating
5. ✅ Shows next steps to restart the proxy service

**Follow the prompts:**
- Open http://localhost:3002 in your browser
- Go to Settings → API Keys → Create New Key
- Copy and paste the key when prompted

**Option 2: Manual Configuration**

1. **Login to Flowise:** http://localhost:3002
2. **Generate Key:** Click profile icon → Settings → API Keys → Create New Key
3. **Copy the key** (e.g., `A27MfYLThKBwYcpDb2M9s6rwXIwUAly9P8j_ujX_J9I`)
4. **Update config:**
   ```batch
   cd flowise-proxy-service-py
   notepad .env
   ```
5. **Find and update:**
   ```env
   FLOWISE_API_KEY=A27MfYLThKBwYcpDb2M9s6rwXIwUAly9P8j_ujX_J9I
   ```
6. Save and close

### Step 6: Start Other Services

**Required for complete platform functionality.** Skip only if you want Flowise standalone.

**Auth Service:**
```batch
cd ..\auth-service
start.bat
```

**Accounting Service:**
```batch
cd ..\accounting-service
start.bat
```

**Flowise Proxy Service:**
```batch
cd ..\flowise-proxy-service-py
start.bat
```

**Bridge UI:**
```batch
cd ..\bridge
start.bat
```

### Step 7: Create Admin and Users

**Create users from CSV:**
```batch
cd auth-service\quickCreateAdminPy
manage_users_admin.bat
```

⚠️ **Note:** Right-click and select "Run as administrator"

**Default Admin Credentials:**
- **Username:** `admin`
- **Email:** `admin@example.com`
- **Password:** `admin@admin`

**Manage users via CSV:**
```batch
notepad users.csv    # Edit users
sync_all_users.bat   # Apply changes
```

**CSV Format:**
| action | username  | email              | password   | role    | fullName      | credits |
|--------|-----------|-------------------|------------|---------|---------------|---------|
| create | teacher1  | teacher1@school.com| Teacher1!  | teacher | Teacher One   | 5000    |
| create | student1  | student1@school.com| Student1!  | student | Student One   | 1000    |

---

## 🔍 Troubleshooting

### Debug Script

If services won't start, run the debug script:
```batch
cd flowise
debug.bat
```

This generates a comprehensive log showing:
- ✓ Environment variables
- ✓ Docker configuration  
- ✓ Container status
- ✓ Container logs
- ✓ Network status

### Common Issues

**1. "network chatproxy-network declared as external, but could not be found"**
- **Fixed:** Docker Compose now auto-creates the network
- **Solution:** Run `git pull` to get the latest `docker-compose.yml`

**2. "Database is uninitialized and superuser password is not specified"**
- **Cause:** Old PostgreSQL data exists without password
- **Solution:** 
  ```batch
  docker compose down -v
  rmdir /s /q D:\DockerVolumes\flowise-postgres
  start-with-postgres.bat
  ```

**3. "Your local changes would be overwritten by merge"**
- **Solution:**
  ```batch
  git stash
  git pull
  ```

**4. Port already in use**
- **Check ports:**
  ```batch
  netstat -ano | findstr ":3002 :3001 :3000"
  ```
- **Kill process:** Find PID and use Task Manager

**5. Container won't start**
- **View logs:**
  ```batch
  docker logs flowise -f
  docker logs flowise-postgres -f
  ```

---

## 📊 Drive Configuration (Optional)

If your system has multiple drives (especially RAID), optimizing storage can provide better performance and redundancy.

**Run automated configuration:**
```batch
configure_drives.bat
```

**What it does:**
1. Detects available drives (C:, D:, E:, etc.)
2. Checks for RAID configuration
3. Recommends optimal storage paths
4. Updates docker-compose.yml files
5. Creates directory structure

**Created directories:**
```
D:\DockerVolumes\
├── mongodb-auth\
├── mongodb-proxy\
├── postgres-accounting\
└── flowise-postgres\

D:\ChatProxyData\
├── uploads\
├── logs\
└── backups\
```

See [check_drives_and_setup.bat](check_drives_and_setup.bat) for manual configuration.

---

## 📚 Service Endpoints

| Service | Endpoint | Purpose |
|---------|----------|---------|
| **Flowise** | http://localhost:3002 | AI Flow Builder |
| **Auth Service** | http://localhost:3000 | Authentication API |
| **Accounting Service** | http://localhost:3001 | Credit Management |
| **Flowise Proxy** | http://localhost:8001 | Proxy Service |
| **Bridge UI** | http://localhost:3082 | Frontend |
| **MailHog UI** | http://localhost:8025 | Email Testing |

---

## 🔐 Admin Credentials

### Flowise Admin
- **Email:** `ecysit@eduhk.hk`
- **Password:** `Admin@2026`
- **Access:** http://localhost:3002

### Auth Service Admin
- **Username:** `admin`
- **Email:** `admin@example.com`
- **Password:** `admin@admin`

---

## 📝 Management Commands

### System Health
```batch
check_system.bat           # Comprehensive system check
diagnose_setup.bat         # Detailed diagnostics
```

### Flowise
```batch
cd flowise
start-with-postgres.bat    # Start
stop.bat                   # Stop
debug.bat                  # Troubleshoot
```

### Auth Service
```batch
cd auth-service
start.bat                  # Start
stop.bat                   # Stop
rebuild.bat                # Rebuild after changes
logs.bat                   # View logs
```

### Accounting Service
```batch
cd accounting-service
start.bat                  # Start
stop.bat                   # Stop
rebuild.bat                # Rebuild
logs.bat                   # View logs
```

### Flowise Proxy
```batch
cd flowise-proxy-service-py
docker compose up -d       # Start
docker compose down        # Stop
docker compose restart     # Restart
logs.bat                   # View logs
```

### Bridge UI
```batch
cd bridge
start.bat                  # Start
stop.bat                   # Stop
rebuild.bat                # Rebuild
logs.bat                   # View logs
```

### User Management
```batch
cd auth-service\quickCreateAdminPy
notepad users.csv          # Edit users/credits
sync_all_users.bat         # Apply all changes
list_users.bat             # List all users
```

---

## 💾 Backup and Restore

### Create Backup

```batch
# MongoDB (Auth)
docker exec mongodb-auth mongodump --out /backup
docker cp mongodb-auth:/backup D:\ChatProxyData\backups\mongodb-auth

# PostgreSQL (Flowise)
docker exec flowise-postgres pg_dump -U flowiseuser flowise > D:\ChatProxyData\backups\flowise.sql

# PostgreSQL (Accounting)
docker exec postgres-accounting pg_dump -U postgres accounting > D:\ChatProxyData\backups\accounting.sql

# Configuration files
copy auth-service\quickCreateAdminPy\users.csv D:\ChatProxyData\backups\
```

### Restore from Backup

**MongoDB:**
```batch
docker cp D:\ChatProxyData\backups\mongodb-auth mongodb-auth:/backup
docker exec mongodb-auth mongorestore /backup
```

**PostgreSQL:**
```batch
type D:\ChatProxyData\backups\flowise.sql | docker exec -i flowise-postgres psql -U flowiseuser flowise
```

---

## 🔒 Security Notes

⚠️ **IMPORTANT:** The default credentials provided here are for **development only**. 

Before deploying to production:
1. ✅ Change all default passwords
2. ✅ Update JWT secrets in `.env`
3. ✅ Configure proper CORS origins
4. ✅ Enable HTTPS
5. ✅ Set up proper database backups
6. ✅ Review drive configuration for RAID/redundancy
7. ✅ Implement automated backup schedule

---

## 📖 Additional Documentation

- [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md) - Detailed deployment guide
- [README.md](README.md) - Project overview
- [docs/SERVICE_ARCHITECTURE.md](docs/SERVICE_ARCHITECTURE.md) - Architecture details
- [docs/JWT_AUTHENTICATION_FIXES.md](docs/JWT_AUTHENTICATION_FIXES.md) - Authentication details

---

## 💡 Support

For issues or questions:

**Quick Diagnostics:**
1. Run `check_system.bat` for comprehensive system check
2. Run `diagnose_setup.bat` for detailed diagnostics
3. Run `cd flowise && debug.bat` for Flowise-specific issues
4. Check service logs: `logs.bat` in each service directory

**Common Commands:**
```batch
docker ps -a               # Check container status
docker network ls          # Check networks
docker logs <container>    # View container logs
netstat -ano | findstr :3002  # Check port usage
```

---

**Last Updated:** February 12, 2026
