# ChatProxyPlatform - Multi-Computer Deployment Checklist

This checklist ensures smooth installation on multiple computers.

## Pre-Installation Requirements

### ✅ Required Software

1. **Docker Desktop** (Required)
   - Download: https://www.docker.com/products/docker-desktop/
   - Ensure it's running before installation
   - Enable WSL 2 backend if on Windows

2. **Node.js LTS** (Required)
   - Download: https://nodejs.org/
   - Or install via winget: `winget install OpenJS.NodeJS.LTS`
   - Verify: `node --version` and `npm --version`

3. **Python 3.8+** (Required)
   - Download: https://www.python.org/downloads/
   - Check "Add Python to PATH" during installation
   - Verify: `python --version`

4. **Git** (Recommended)
   - Download: https://git-scm.com/downloads
   - Or install via winget: `winget install Git.Git`
   - Verify: `git --version`

### ✅ System Requirements

- **Operating System**: Windows 10/11
- **RAM**: Minimum 8GB (16GB recommended)
- **Disk Space**: Minimum 10GB free (preferably on D: drive)
- **Admin Rights**: Run installation as Administrator

### ✅ Drive Configuration

The installer will automatically:
- ✓ Prefer **D: drive** for Docker volumes (if 10GB+ available)
- ✓ Fall back to drive with most free space
- ✓ Create necessary directories

**Recommended**: Have D: drive available with 20GB+ free space

---

## Installation Steps

### Step 1: Download Repository
```bash
# Clone the repository
git clone <repository_url> C:\ChatProxyPlatform
cd C:\ChatProxyPlatform
```

Or download as ZIP and extract to `C:\ChatProxyPlatform`

### Step 2: Run Automated Setup

**Option A: Run as Administrator (Recommended)**
1. Right-click `automated_setup.bat`
2. Select "Run as Administrator"
3. Follow on-screen prompts

**Option B: PowerShell**
```powershell
# Run as Administrator
cd C:\ChatProxyPlatform
.\automated_setup.bat
```

### Step 3: Follow Setup Wizard

The automated setup will:
1. ✓ Check system requirements (Docker, Python, Node.js, Git)
2. ✓ Detect available drives and select optimal storage
3. ✓ Configure Docker volumes on selected drive (prefers D:)
4. ✓ Generate security secrets
5. ✓ Start Flowise service
6. ✓ Prompt for Flowise API key
7. ✓ Configure all microservices
8. ✓ Start auth and accounting services
9. ✓ Create admin user
10. ✓ Deploy bridge UI

**Important**: When prompted for Flowise API key:
1. Open http://localhost:3002 in browser
2. Create account or login
3. Go to Settings → API Keys
4. Copy the API key
5. Paste into terminal

---

## Post-Installation Verification

### ✅ Check Services Running

```powershell
docker ps
```

Expected containers:
- `flowise` (port 3002)
- `flowise-postgres`
- `auth-service` (port 3000)
- `mongodb-auth`
- `mailhog` (port 8025)
- `accounting-service` (port 3001)
- `postgres-accounting`
- `flowise-proxy-service-py` (port 5001)
- `mongodb-proxy`
- `bridge` (port 8080)

### ✅ Test Endpoints

1. **Flowise**: http://localhost:3002
2. **Auth Service**: http://localhost:3000/health
3. **Accounting Service**: http://localhost:3001/health
4. **Flowise Proxy**: http://localhost:5001/health
5. **Bridge UI**: http://localhost:8080
6. **MailHog** (email testing): http://localhost:8025

### ✅ Login Credentials

**Admin Account:**
- Username: `admin`
- Email: `admin@example.com`
- Password: `Admin123!`
- Verify email at: http://localhost:8025 (MailHog)

---

## Troubleshooting

### Docker Not Running
```
Error: Docker daemon is not running
```
**Solution**: Start Docker Desktop and wait for it to initialize

### Node.js Not Found
```
Error: 'npm' is not recognized
```
**Solution**: 
1. Install Node.js LTS from https://nodejs.org/
2. Restart terminal/command prompt
3. Verify with: `node --version`

### Permission Denied (Drive Access)
```
Error: Permission denied creating D:\DockerVolumes
```
**Solution**: 
- Run `automated_setup.bat` as Administrator
- OR let it fall back to workspace directory (automatic)

### Port Already in Use
```
Error: Bind for 0.0.0.0:3000 failed: port is already allocated
```
**Solution**:
```powershell
# Find and stop conflicting service
docker ps -a
docker stop <container_id>
```

### Container Build Failed
```
Error: failed to solve: failed to compute cache key
```
**Solution**:
1. Ensure you're in the correct directory
2. Check that `package.json` and `package-lock.json` exist
3. Try: `docker system prune -a` (warning: removes all unused containers)
4. Re-run setup

---

## Deployment to Multiple Computers

### Quick Deployment Method

1. **Prepare Installation Package**
   - Copy entire `ChatProxyPlatform` folder
   - Include this checklist

2. **On Each Computer**
   ```powershell
   # Install prerequisites (one-time per computer)
   winget install Docker.DockerDesktop
   winget install OpenJS.NodeJS.LTS
   winget install Python.Python.3.12
   
   # Start Docker Desktop and wait for it to be ready
   
   # Run setup
   cd C:\ChatProxyPlatform
   .\automated_setup.bat
   ```

3. **Automated Installation Script** (Optional)
   Create `quick_install.bat`:
   ```batch
   @echo off
   echo Installing prerequisites...
   winget install -e --id Docker.DockerDesktop --silent
   winget install -e --id OpenJS.NodeJS.LTS --silent
   winget install -e --id Python.Python.3.12 --silent
   
   echo.
   echo Please start Docker Desktop manually, then press any key...
   pause
   
   echo Running automated setup...
   call automated_setup.bat
   ```

---

## Best Practices

✓ **Always use D: drive** when available (automatic)
✓ **Run as Administrator** for first installation
✓ **Start Docker Desktop** before running setup
✓ **Verify all endpoints** after installation
✓ **Backup .env files** before re-running setup
✓ **Document custom configurations** (API keys, ports, etc.)

---

## Quick Reference

| Service | Default Port | Health Check |
|---------|--------------|--------------|
| Flowise | 3002 | http://localhost:3002 |
| Auth Service | 3000 | http://localhost:3000/health |
| Accounting Service | 3001 | http://localhost:3001/health |
| Flowise Proxy | 5001 | http://localhost:5001/health |
| Bridge UI | 8080 | http://localhost:8080 |
| MailHog | 8025 | http://localhost:8025 |

---

## Support

For issues or questions:
1. Check logs: `docker logs <container_name>`
2. Review setup output for error messages
3. Verify all prerequisites are installed
4. Ensure sufficient disk space on selected drive

---

## Notes

- First installation takes 10-15 minutes
- Docker images are downloaded automatically
- Database data persists between restarts
- Re-running setup preserves existing configurations (with prompts)
