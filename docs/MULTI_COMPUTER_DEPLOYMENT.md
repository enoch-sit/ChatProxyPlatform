# Multi-Computer Deployment Guide

This guide helps you deploy ChatProxyPlatform on multiple computers quickly and reliably.

## 🎯 What's Fixed

The automated setup script now:
- ✅ **Uses D: drive by default** (when available with >10GB free)
- ✅ **Works from any directory** (uses script's location, not current directory)
- ✅ **Checks for Node.js** before starting (prevents npm errors)
- ✅ **Shows workspace location** during setup
- ✅ **Handles path issues** automatically

## 🚀 Quick Start (3 Methods)

### Method 1: Quick Install (Recommended for New Computers)

**Installs everything automatically:**
```batch
quick_install.bat
```

This will:
1. Install Docker Desktop, Node.js, Python, Git (via winget)
2. Prompt you to restart terminal and start Docker
3. Run automated setup

### Method 2: Automated Setup (If Prerequisites Already Installed)

**If Docker, Node.js, Python already installed:**
```batch
automated_setup.bat
```

Requirements:
- Docker Desktop running
- Node.js LTS installed
- Python 3.8+ installed

### Method 3: Manual Installation

**Follow the detailed checklist:**
```
See: DEPLOYMENT_CHECKLIST.md
```

## 📋 Prerequisites Checklist

Before running on **each computer**:

| Requirement | Check Command | Install |
|-------------|---------------|---------|
| Docker Desktop | `docker --version` | https://docker.com |
| Node.js LTS | `node --version` | https://nodejs.org |
| Python 3.8+ | `python --version` | https://python.org |
| Git (optional) | `git --version` | https://git-scm.com |

**Quick Install All** (Windows 11):
```powershell
winget install Docker.DockerDesktop
winget install OpenJS.NodeJS.LTS
winget install Python.Python.3.12
winget install Git.Git
```

## 💾 Storage Configuration

The script automatically:
1. **Prefers D: drive** if available with >10GB free
2. Falls back to drive with most free space
3. Uses local directory if no suitable drive found

**Recommended**: Have D: drive with 20GB+ free space

## 📝 Installation Process

### On Each Computer:

1. **Copy Repository**
   ```batch
   # Extract or clone to C:\ChatProxyPlatform
   cd C:\ChatProxyPlatform
   ```

2. **Start Docker Desktop**
   - Launch Docker Desktop
   - Wait for green checkmark in system tray

3. **Run Installation**
   ```batch
   # Option A: Full automatic (installs prerequisites)
   quick_install.bat
   
   # Option B: Prerequisites already installed
   automated_setup.bat
   ```

4. **Follow Prompts**
   - System checks (Docker, Python, Node.js, Git)
   - Drive selection (automatic - prefers D:)
   - Flowise API key (http://localhost:3002)
   - Service configuration (automatic)

5. **Access Services**
   - Bridge UI: http://localhost:8080
   - Flowise: http://localhost:3002
   - MailHog: http://localhost:8025

## 🔧 Common Issues & Solutions

### ❌ "npm is not recognized"
**Problem**: Node.js not installed or not in PATH

**Solution**:
```powershell
# Install Node.js
winget install OpenJS.NodeJS.LTS

# Restart terminal
exit

# Then re-run setup
cd C:\ChatProxyPlatform
automated_setup.bat
```

### ❌ "Docker daemon is not running"
**Problem**: Docker Desktop not started

**Solution**:
1. Open Docker Desktop from Start Menu
2. Wait for green checkmark in system tray
3. Re-run `automated_setup.bat`

### ❌ "Permission denied creating D:\DockerVolumes"
**Problem**: Not running as Administrator

**Solution**:
1. Right-click `automated_setup.bat`
2. Select "Run as Administrator"
3. Or let it use local directory automatically

### ❌ "package-lock.json not found"
**Problem**: Wrong working directory (FIXED in latest version)

**Solution**:
- Update to latest `automated_setup.py` (already fixed)
- Or ensure you're in the correct directory

## 🎓 For IT Administrators

### Batch Deployment Script

Create `deploy_all.ps1`:
```powershell
# Deploy to multiple computers
$computers = @("PC1", "PC2", "PC3")

foreach ($pc in $computers) {
    Write-Host "Deploying to $pc..." -ForegroundColor Cyan
    
    # Copy files
    Copy-Item -Path ".\ChatProxyPlatform" -Destination "\\$pc\C$\" -Recurse -Force
    
    # Run installation remotely
    Invoke-Command -ComputerName $pc -ScriptBlock {
        cd C:\ChatProxyPlatform
        Start-Process "automated_setup.bat" -Wait
    }
}
```

### Pre-configured Installation Package

1. Set up one computer completely
2. Copy these files:
   - All `.env` files (contains JWT secrets)
   - `flowise-proxy-service-py/.env` (Flowise API key)
3. Distribute package to other computers
4. Run `automated_setup.bat` (will reuse existing configs)

## 📊 Verification

After installation on each computer:

```powershell
# Check all services running
docker ps

# Test endpoints
curl http://localhost:3000/health  # Auth Service
curl http://localhost:3001/health  # Accounting Service
curl http://localhost:5001/health  # Flowise Proxy
curl http://localhost:8080         # Bridge UI
```

Expected containers (9):
- flowise
- flowise-postgres
- auth-service
- mongodb-auth
- mailhog
- accounting-service
- postgres-accounting
- flowise-proxy-service-py
- mongodb-proxy
- bridge

## 📚 Documentation

- **Quick Reference**: See table in DEPLOYMENT_CHECKLIST.md
- **Detailed Setup**: See DEPLOYMENT_CHECKLIST.md
- **Troubleshooting**: See DEPLOYMENT_CHECKLIST.md
- **Architecture**: See docs/SERVICE_ARCHITECTURE.md

## 🔄 Updating Existing Installations

```batch
# Pull latest changes
git pull

# Re-run setup (preserves data)
automated_setup.bat

# Choose to reuse or regenerate configs at each prompt
```

## ✅ Success Indicators

Setup is successful when:
- ✓ All 9 Docker containers running
- ✓ Bridge UI accessible at http://localhost:8080
- ✓ Can login with admin credentials
- ✓ No errors in `docker ps` output
- ✓ Health endpoints return 200 OK

## 🆘 Getting Help

If you encounter issues:
1. Check `DEPLOYMENT_CHECKLIST.md` for detailed troubleshooting
2. Review Docker logs: `docker logs <container_name>`
3. Verify all prerequisites installed: Run `automated_setup.bat` again
4. Ensure sufficient disk space on D: drive (or selected drive)

---

**Need Quick Help?**
- Installation time: ~10-15 minutes per computer
- Requirements: Docker, Node.js, Python
- Default admin: `admin@example.com` / `Admin123!`
- Verify email at: http://localhost:8025 (MailHog)
