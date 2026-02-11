# Windows Docker Deployment - Complete Setup Guide

Complete step-by-step guide to deploy the ChatProxy Platform on Windows using Docker.

---

## 🚀 Quick Start

**After Git Clone (IMPORTANT - First Time Setup):**

If you just cloned the repository, **you must create `.env` files first** (they're not in git):

```batch
# 1. Clone the repository (if not done yet)
git clone https://github.com/enoch-sit/ChatProxyPlatform.git
cd ChatProxyPlatform

# 2. Create all .env files from templates
setup_env_files.bat

# 3. Generate and populate JWT secrets automatically
generate_secrets.bat
```

**For fresh Windows installations (after .env setup):**
1. **Configure drives** - Run **`configure_drives.bat`** to automatically detect RAID and optimize storage paths
2. Read the complete **[DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md)** - step-by-step guide for beginners
3. Track your progress with **[DEPLOYMENT_PROGRESS.md](DEPLOYMENT_PROGRESS.md)** - printable checklist
4. Run **`check_system.bat`** - automated system checker for prerequisites

**For existing installations:**
Continue with this guide below.

---

## 🔧 Prerequisites Setup

### Initial Repository Setup (Git Clone)

**CRITICAL:** After cloning the repository, `.env` files don't exist (they're in `.gitignore`). You must create them:

#### Step 1: Create Environment Files

**What files are needed?**

The platform requires `.env` configuration files for all 5 services:
1. ✅ `flowise/.env` - Flowise AI + PostgreSQL configuration
2. ✅ `auth-service/.env` - Authentication service + MongoDB + JWT secrets
3. ✅ `accounting-service/.env` - Accounting service + PostgreSQL + JWT secrets
4. ✅ `flowise-proxy-service-py/.env` - Proxy service + MongoDB + JWT secrets
5. ✅ `bridge/.env` - Frontend React app configuration

**Automated Setup (Recommended):**

Run the automated setup script:
```batch
setup_env_files.bat
```

**What it does:**
- ✅ Scans all 5 services for `.env.example` templates
- ✅ Copies each `.env.example` → `.env` if not already exists
- ✅ Skips if `.env` already exists (safe to re-run)
- ✅ Shows color-coded summary (copied/skipped/errors)
- ✅ Provides next steps for JWT secret generation

**Expected output:**
```
╔════════════════════════════════════════════════════════════════╗
║   ChatProxy Platform - Environment File Setup                  ║
║   Creating .env files from templates                           ║
╚════════════════════════════════════════════════════════════════╝

[OK] Flowise AI Flow Builder - Created .env file
[OK] Authentication Service - Created .env file
[OK] Accounting Service - Created .env file
[OK] Flowise Proxy Service - Created .env file
[OK] Bridge UI Frontend - Created .env file

════════════════════════════════════════════════════════════════
Summary:
  ✓ Copied: 5
  ○ Skipped: 0
  ✗ Errors: 0
════════════════════════════════════════════════════════════════
```

**Manual alternative (if script fails):**
```batch
copy flowise\.env.example flowise\.env
copy auth-service\.env.example auth-service\.env
copy accounting-service\.env.example accounting-service\.env
copy flowise-proxy-service-py\.env.example flowise-proxy-service-py\.env
copy bridge\.env.example bridge\.env
```

**Verify all files were created:**
```powershell
# Check if all .env files exist
Test-Path flowise\.env
Test-Path auth-service\.env
Test-Path accounting-service\.env
Test-Path flowise-proxy-service-py\.env
Test-Path bridge\.env
```

All should return `True`.

⚠️ **IMPORTANT:** The script creates files but does NOT fill in JWT secrets. Continue to Step 2.

#### Step 2: Generate and Populate JWT Secrets

**CRITICAL:** JWT secrets must be **identical** across three services (auth-service, accounting-service, flowise-proxy).

**Automated secret generation (Recommended):**
```batch
generate_secrets.bat
```

**What it does:**
- ✅ Generates 64-character cryptographically secure JWT secrets
- ✅ Generates 32-character secure database passwords (PostgreSQL & MongoDB)
- ✅ Automatically updates all .env files with matching secrets
- ✅ Updates JWT secrets in 3 services (auth, accounting, proxy)
- ✅ Updates PostgreSQL passwords in 2 services (flowise, accounting)
- ✅ Updates MongoDB passwords in 2 services (auth, proxy)
- ✅ Creates backup files (.env.backup) before updating
- ✅ Verifies all files exist before proceeding
- ✅ Shows color-coded success/error messages
- ⚠️ **Note:** FLOWISE_API_KEY must be created AFTER Flowise starts (see Step 3 below)

**Expected output:**
```
══════════════════════════════════════════════════════════════════
ChatProxy Platform - JWT Secret Generator
══════════════════════════════════════════════════════════════════

ℹ Workspace: C:\Users\user\...\ThankGodForChatProxyPlatform
ℹ Checking for .env files...
✓ auth-service/.env found
✓ accounting-service/.env found
✓ flowise-proxy-service-py/.env found
✓ flowise/.env found

ℹ Generating cryptographically secure secrets...
✓ JWT_ACCESS_SECRET: a1b2c3d4e5f6g7h8i9j0... (64 chars)
✓ JWT_REFRESH_SECRET: z9y8x7w6v5u4t3s2r1q0... (64 chars)
✓ POSTGRES_PASSWORD: yPaIO==HdzSXGu&+... (32 chars)
✓ MONGO_PASSWORD: f1Nf%q!Mb%QdF%LF... (32 chars)

ℹ Updating .env files with JWT secrets...
✓ auth-service/.env updated with JWT secrets
✓ accounting-service/.env updated with JWT secrets
✓ flowise-proxy-service-py/.env updated with JWT secrets

ℹ Updating database passwords...
✓ flowise (PostgreSQL) password updated
✓ accounting-service (PostgreSQL) password updated
✓ auth-service (MongoDB) password updated
✓ flowise-proxy-service-py (MongoDB) password updated

══════════════════════════════════════════════════════════════════
Summary
══════════════════════════════════════════════════════════════════
✓ All 7 updates completed successfully!
✓ Same JWT secrets in auth, accounting, and proxy services
✓ PostgreSQL passwords updated in flowise and accounting
✓ MongoDB passwords updated in auth and proxy services

ℹ Backups created: <service>/.env.backup
ℹ Next step: Start services with docker compose
```

**Verify secrets were populated:**
```powershell
# Check that JWT secrets are present and identical
findstr "JWT_ACCESS_SECRET" auth-service\.env accounting-service\.env flowise-proxy-service-py\.env

# Check that database passwords were set
findstr "POSTGRES_PASSWORD" flowise\.env accounting-service\.env
```

All JWT secrets should show **identical values** (not placeholders like `your-secret-key-here`).

**Manual alternative (if automated script fails):**
```powershell
# 1. Generate secrets using Python directly
python generate_secrets.py

# 2. If Python script fails, manually edit .env files:
#    - auth-service\.env
#    - accounting-service\.env  
#    - flowise-proxy-service-py\.env
#
# Generate 64-char random strings and paste SAME values in all three!
```

---

## 📊 Drive Configuration (Optional but Recommended)

### Why Configure Drives?

If your system has multiple drives (especially RAID), optimizing storage locations can provide:
- ✅ Better performance (separate database I/O from system drive)
- ✅ Data redundancy (RAID protection)
- ✅ More capacity for data growth
- ✅ Easier backup management

### Automated Drive Configuration

**Step 1: Run the configuration tool**
```batch
configure_drives.bat
```

**What it does:**
1. Detects available drives (C:, D:, E:, etc.)
2. Checks for RAID configuration (hardware and software)
3. Calculates free space on each drive
4. Recommends optimal storage configuration
5. Offers to:
   - Preview changes (dry-run)
   - Apply changes automatically
   - Create directory structure

**Step 2: Choose your option**
- **[1] Preview changes** - See what will be updated without modifying files
- **[2] Apply changes** - Update docker-compose.yml and .env files automatically
- **[3] Cancel** - Exit without changes

**What gets updated:**
- `auth-service/docker-compose.dev.yml` - MongoDB volume paths
- `accounting-service/docker-compose.yml` - PostgreSQL volume paths
- `flowise/docker-compose.yml` - PostgreSQL volume paths
- `flowise-proxy-service-py/docker-compose.yml` - MongoDB volume paths
- `flowise-proxy-service-py/.env` - File storage and log paths

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

**Safety features:**
- ✅ Always creates backups before modifying files
- ✅ Preserves YAML formatting and comments
- ✅ Validates changes before applying
- ✅ Dry-run mode to preview first

### Manual Drive Configuration

If you prefer manual configuration or want to use a custom drive:

1. **Edit docker-compose.yml files** - Update volume paths to your preferred location
2. **Edit .env files** - Update FILE_STORAGE_PATH and LOG_PATH
3. **Create directories** - Manually create required folders
4. **Restart services** - Apply the new configuration

See [check_drives_and_setup.bat](check_drives_and_setup.bat) for detailed manual instructions.

---

## Prerequisites

- Docker Desktop installed and running
- Git (for cloning the repository)
- Python 3.x installed
- Windows PowerShell or Command Prompt
- **Optional:** D: drive with RAID for optimal data storage

**Quick Check:** Run `check_system.bat` to verify all prerequisites are met.

---

## Step 1: Launch Flowise with PostgreSQL

### 1.1 Start Flowise Docker Container

```batch
cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\flowise
start-with-postgres.bat
```

**Wait for containers to start** (check status: `docker ps`)

### 1.2 Access Flowise Web Interface

Open your browser and navigate to:
```
http://localhost:3002
```

**Note:** Flowise now uses **PostgreSQL** instead of SQLite for better performance and reliability.

### 1.3 Setup Flowise Admin Account

On first access, Flowise will prompt you to create an admin account:

- **Name:** `admin`
- **Email:** `ecysit@eduhk.hk`
- **Password:** `Admin@2026`

**Important:** Complete the initial setup wizard and save your credentials.

---

## Step 3: Configure Flowise API Key (Post-Deployment)

⚠️ **CRITICAL:** This step MUST be done AFTER Flowise is running. The API key cannot be generated before Flowise starts.

### 3.1 Generate Flowise API Key

The Flowise Proxy Service requires an API key to sync chatflows from Flowise.

**Option A: Automated Configuration (Recommended)**

```batch
# Run the interactive configuration script
configure_flowise_api.bat
```

This interactive script will:
1. Show you step-by-step instructions to get the API key from Flowise UI
2. Prompt you to enter the API key
3. Validate the key format
4. Automatically update `flowise-proxy-service-py/.env`
5. Create a backup before making changes
6. Display next steps for restarting the service

**Follow the on-screen prompts:**
1. **Login to Flowise:** Open http://localhost:3002 (login: ecysit@eduhk.hk / Admin@2026)
2. **Generate API Key:** Settings → API Keys → Create New Key
3. **Copy the key** and paste it when prompted
4. **Restart the service** as instructed

---

**Option B: Manual Configuration**

If you prefer manual setup:

1. **Login to Flowise:**
   - Open http://localhost:3002
   - Login with your admin credentials (ecysit@eduhk.hk / Admin@2026)

2. **Generate API Key:**
   - Click on your profile icon (top-right corner)
   - Navigate to **Settings** → **API Keys**
   - Click **Add New Key** or **Generate API Key**
   - Copy the generated API key (e.g., `A27MfYLThKBwYcpDb2M9s6rwXIwUAly9P8j_ujX_J9I`)

3. **Configure Flowise Proxy:**
   - Open the Flowise Proxy `.env` file:
     ```batch
     cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\flowise-proxy-service-py
     notepad .env
     ```
   - Find the line: `FLOWISE_API_KEY=`
   - Paste your API key: `FLOWISE_API_KEY=A27MfYLThKBwYcpDb2M9s6rwXIwUAly9P8j_ujX_J9I`
   - Save and close the file

4. **Restart Flowise Proxy** (if already running):
   ```batch
   cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\flowise-proxy-service-py
   docker compose restart
   ```

**Note:** Without the API key, chatflow synchronization will fail with "401 Unauthorized" errors.

---

## Step 4: Generate JWT Secrets (Security Setup)

### 4.1 Why Generate JWT Secrets?

JWT (JSON Web Token) secrets are used to sign authentication tokens across all services. For security:
- ✅ **Same secrets** must be used in auth-service, accounting-service, and flowise-proxy
- ✅ **Unique secrets** should be generated for each deployment
- ✅ **Strong secrets** prevent token forgery and unauthorized access

### 4.2 Generate Secrets Automatically

**Automated JWT Secret Generation (Recommended)**

```batch
# Run the automated secret generator
generate_secrets.bat
```

This will automatically:
- Generate cryptographically secure 64-character JWT secrets
- Update all three .env files with identical secrets
- Create backup files before updating
- Verify all files exist
- ⚠️ **NOTE:** You'll still need to manually add FLOWISE_API_KEY from Step 3

**Output:**
```
ChatProxy Platform - JWT Secret Generator

ℹ Checking for .env files...
✓ auth-service/.env found
✓ accounting-service/.env found
✓ flowise-proxy-service-py/.env found

ℹ Generating cryptographically secure JWT secrets...
✓ JWT_ACCESS_SECRET: a1b2c3d4e5f6g7h8i9j0... (64 chars)
✓ JWT_REFRESH_SECRET: z9y8x7w6v5u4t3s2r1q0... (64 chars)
MONGO_PASSWORD=1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p
POSTGRES_PASSWORD=9z8y7x6w5v4u3t2s1r0q9p8o7n6m5l4k

IMPORTANT: Use the SAME JWT secrets across all three services!
```

**Option B: Node.js Command**

```batch
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

Run twice to generate `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET`.

**Option C: PowerShell One-liner**

```powershell
[System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N')
```

### 2.3 Update .env Files

**CRITICAL:** JWT secrets must be **identical** across these three services:

#### **1. auth-service/.env**

```batch
cd auth-service
notepad .env
```

Update these lines:
```env
JWT_ACCESS_SECRET=your_generated_access_secret_here
JWT_REFRESH_SECRET=your_generated_refresh_secret_here
JWT_ACCESS_EXPIRES_IN=1h
JWT_REFRESH_EXPIRES_IN=7d
```

#### **2. accounting-service/.env**

```batch
cd ..\accounting-service
notepad .env
```

Update these lines (use the **SAME values** as auth-service):
```env
JWT_ACCESS_SECRET=your_generated_access_secret_here
JWT_REFRESH_SECRET=your_generated_refresh_secret_here
```

#### **3. flowise-proxy-service-py/.env**

```batch
cd ..\flowise-proxy-service-py
notepad .env
```

Update these lines (use the **SAME values** as auth-service):
```env
JWT_ACCESS_SECRET=your_generated_access_secret_here
JWT_REFRESH_SECRET=your_generated_refresh_secret_here
```

### 2.4 Security Best Practices

✅ **Do:**
- Generate unique secrets for each deployment (dev, staging, production)
- Use secrets that are at least 32 characters long
- Keep secrets in `.env` files (never commit to git)
- Use the same JWT secrets across all services
- Rotate secrets periodically (every 90 days)

❌ **Don't:**
- Use default/example secrets in production
- Commit `.env` files to version control
- Share secrets via email or chat
- Use different JWT secrets between services (tokens won't validate)

### 2.5 Verify Configuration

Before starting services, verify all three `.env` files have:
- ✅ Same `JWT_ACCESS_SECRET`
- ✅ Same `JWT_REFRESH_SECRET`
- ✅ `JWT_ACCESS_EXPIRES_IN=1h` (auth-service only)
- ✅ `JWT_REFRESH_EXPIRES_IN=7d` (auth-service only)

**Quick check:**
```powershell
# Compare JWT secrets across services
findstr "JWT_ACCESS_SECRET" auth-service\.env accounting-service\.env flowise-proxy-service-py\.env
```

All three should show the same value.

---
5: Launch Auth Service

### 5
### 3.1 Start Auth Service Containers

```batch
cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\auth-service
start.bat
```

**Services Started:**
- Auth Service: `http://localhost:3000`
- MongoDB: `localhost:27017`
- MailHog UI: `http://localhost:8025`

### 2.2 Create Admin Account

```batch
cd quickCreateAdminPy
setup_and_run.bat
```

**Default Admin Credentials:**
- **Username:** `admin`
- **Email:** `admin@example.com`
- **Password:** `admin@admin`

### 5.3 Verify Admin Account

After the script completes, verify the admin account was created successfully by checking the output or running:

```batch
list_users.bat
```

---

## Step 6: Manage Users and Credits (CSV-Based System)

### 6.1 Overview

The platform includes a simple CSV-based system for managing users and credits - perfect for teachers without computer knowledge!

**What you can do:**
- Create new teacher and student accounts
- Remove existing users
- Set and update credit amounts
- All from a simple spreadsheet (Excel/Notepad)

### 6.2 Edit Users in CSV

Navigate to the user management folder:
```batch
cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\auth-service\quickCreateAdminPy
```

Open `users.csv` in Excel or Notepad and edit:

| action | username  | email              | password   | role    | fullName      | credits |
|--------|-----------|-------------------|------------|---------|---------------|---------|
| create | teacher1  | teacher1@school.com| Teacher1!  | teacher | Teacher One   | 5000    |
| create | student1  | student1@school.com| Student1!  | student | Student One   | 1000    |

**Column Guide:**
- **action:** `create` (add user) or `delete` (remove user)
- **username:** Unique username for login
- **email:** User's email address (must be unique)
- **password:** Strong password (8+ characters, letters + numbers)
- **role:** `teacher` (more credits) or `student` (standard user)
- **fullName:** Display name
- **credits:** Amount of AI credits (e.g., 5000 for teachers, 1000 for students)

### 3.3 Apply Changes - One-Click Sync

After editing `users.csv`, simply run:

```batch
sync_all_users.bat
```

**What this does automatically:**
1. Creates new users (action=create)
2. Deletes users (action=delete)
3. Verifies all users (enables login)
4. Initializes users in accounting system
5. Sets/updates credits for all users

**Wait for:** `SUCCESS! All users and credits synchronized`

### 3.4 Common Tasks

#### Add a New Student
1. Open `users.csv` in Excel
2. Add a row: `create,student6,student6@school.com,Student6!,student,John Smith,1000`
3. Save file
4. Run `sync_all_users.bat`

#### Add a New Teacher
1. Open `users.csv` in Excel
2. Add a row: `create,teacher4,teacher4@school.com,Teacher4!,teacher,Jane Doe,5000`
3. Save file
4. Run `sync_all_users.bat`

#### Remove a User
1. Open `users.csv` in Excel
2. Change `create` to `delete` for that user's row
3. Save file
4. Run `sync_all_users.bat`

#### Update Credits
1. Open `users.csv` in Excel
2. Change the number in the `credits` column
3. Save file
4. Run `sync_all_users.bat`

### 3.5 Detailed Instructions

For complete step-by-step instructions designed for non-technical users, see:
```
auth-service\quickCreateAdminPy\TEACHER_GUIDE.md
```

---

## Service Endpoints Summary

| Service | Endpoint | Purpose |
|---------|----------|---------|
| **Flowise** | http://localhost:3002 | AI Flow Builder |
| **Auth Service** | http://localhost:3000 | Authentication API |
| **MailHog UI** | http://localhost:8025 | Email Testing |
| **MongoDB** | localhost:27017 | Auth Database |
| **PostgreSQL** | localhost:5433 | Flowise Database |

---

## Admin Credentials

### Flowise Admin
- **Name:** `admin`
- **Email:** `ecysit@eduhk.hk`
- **Password:** `Admin@2026`
- **Access:** http://localhost:3002
- **API Key:** `A27MfYLThKBwYcpDb2M9s6rwXIwUAly9P8j_ujX_J9I` (configured in flowise-proxy-service-py/.env)

### Auth Service Admin
- **Username:** `admin`
- **Email:** `admin@example.com`
- **Password:** `admin@admin`
- **API:** http://localhost:3000

---

## Next Steps

1. **Manage Users and Credits:**
   ```batch
   cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\auth-service\quickCreateAdminPy
   notepad users.csv              # Edit users
   sync_all_users.bat             # Apply changes
   ```

2. **Test Authentication:**
   ```batch
   cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\auth-service\quickCreateAdminPy
   test_login.bat
   ```

3. **Create Flowise Flow:**
   - Log in to Flowise at http://localhost:3002
   - Create your first chatflow
   - Configure integrations

4. **Launch Additional Services** (if needed):
   - Flowise Proxy Service
   - Accounting Service

5. **Initialize Admin User in Flowise Proxy** (One-time setup):
   ```batch
   cd c:\Users\user\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\flowise-proxy-service-py
   docker exec flowise-proxy python /tmp/sync_admin_chatflows.py
   ```
   
   **This script will automatically:**
   - Create admin user in flowise-proxy database
   - Assign all chatflows from Flowise to admin
   - Allocate 5000 credits to admin in accounting service
   
   **Expected output:**
   ```
   ✅ SETUP COMPLETE!
      User: admin
      Chatflows: 1
      Credits: 5000
   ```

---

## Troubleshooting

### Flowise won't start
- Check port 3002 is not in use: `netstat -ano | findstr :3002`
- View logs: `docker logs flowise -f`

### Auth Service won't start
- Check port 3000 is not in use: `netstat -ano | findstr :3000`
- View logs: `cd auth-service && logs.bat`

### Admin account not created
- Check MongoDB is running: `docker ps | findstr mongodb-auth`
- Manually verify in MongoDB:
  ```batch
  docker exec -i mongodb-auth mongosh auth_db --eval "db.users.find()"
  ```

### Drive configuration issues
- **Permission denied:** Run `configure_drives.bat` as administrator
- **RAID not detected:** Check your storage controller software or run `wmic diskdrive get model`
- **Path update failed:** Check backup folder `config_backup_YYYYMMDD_HHMMSS` and restore if needed
- **Services won't start after path change:** Verify directory structure exists on target drive

### After changing drive configuration
1. **Stop all services:**
   ```batch
   cd flowise && stop.bat
   cd ..\auth-service && stop.bat
   cd ..\accounting-service && stop.bat
   cd ..\flowise-proxy-service-py && docker-compose down
   cd ..\bridge && stop.bat
   ```

2. **Verify directories exist:**
   ```batch
   dir D:\DockerVolumes
   dir D:\ChatProxyData
   ```

3. **Restart services** in order (see Management Commands below)

4. **Run system check:**
   ```batch
   check_system.bat
   ```

---

## Management Commands

### Drive Configuration
```batch
configure_drives.bat       # Automated drive detection and path update
check_drives_and_setup.bat # Interactive manual configuration
```

### System Health
```batch
check_system.bat           # Comprehensive system check
```

### Flowise
```batch
cd flowise
start-with-postgres.bat    # Start
stop.bat                   # Stop
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
rebuild.bat                # Rebuild after changes
logs.bat                   # View logs
```

### Flowise Proxy
```batch
cd flowise-proxy-service-py
docker-compose up -d       # Start
docker-compose down        # Stop
docker-compose restart     # Restart
logs.bat                   # View logs
```

### Bridge UI
```batch
cd bridge
start.bat                  # Start
stop.bat                   # Stop
rebuild.bat                # Rebuild after changes
logs.bat                   # View logs
```

### User Management
```batch
cd auth-service\quickCreateAdminPy
notepad users.csv          # Edit users/credits
sync_all_users.bat         # Apply all changes
```

---

## Backup and Restore

### Automated Backup (Recommended)

If you used `configure_drives.bat`, backups will be stored on your data drive.

**Create manual backup:**
```batch
# MongoDB (Auth)
docker exec mongodb-auth mongodump --out /backup
docker cp mongodb-auth:/backup D:\ChatProxyData\backups\mongodb-auth

# MongoDB (Proxy)
docker exec mongodb mongodump --out /backup
docker cp mongodb:/backup D:\ChatProxyData\backups\mongodb-proxy

# PostgreSQL (Accounting)
docker exec postgres-accounting pg_dump -U postgres accounting > D:\ChatProxyData\backups\accounting.sql

# PostgreSQL (Flowise)
docker exec flowise-postgres pg_dump -U postgres flowise > D:\ChatProxyData\backups\flowise.sql

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
type D:\ChatProxyData\backups\accounting.sql | docker exec -i postgres-accounting psql -U postgres accounting
```

---

## Security Notes

⚠️ **IMPORTANT:** The default credentials provided here are for **development only**. 

Before deploying to production:
1. Change all default passwords
2. Update JWT secrets in `.env`
3. Configure proper CORS origins
4. Enable HTTPS
5. Set up proper database backups
6. Review drive configuration for RAID/redundancy
7. Implement automated backup schedule

---

## Support

For issues or questions:

**Quick Diagnostics:**
1. Run `check_system.bat` for comprehensive system check
2. Check service logs: `logs.bat` in each service directory
3. Docker status: `docker ps -a`
4. Network: `docker network ls`

**Documentation:**
- [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md) - Complete setup guide
- [README.md](README.md) - Project overview
- [docs/SERVICE_ARCHITECTURE.md](docs/SERVICE_ARCHITECTURE.md) - Architecture details
- [docs/JWT_AUTHENTICATION_FIXES.md](docs/JWT_AUTHENTICATION_FIXES.md) - Authentication details

**Common Issues:**
- Port conflicts: `netstat -ano | findstr ":3000 :3001 :3002 :3082 :8000"`
- Docker not running: Check Docker Desktop
- Path issues: Verify drive configuration with `configure_drives.bat`
- Permission issues: Run as administrator

---
