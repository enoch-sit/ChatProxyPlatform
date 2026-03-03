# Universal Login & JWT Diagnostic Tools

**Works on ANY Windows device with Docker Desktop**

## 🎯 Quick Problem Solving

**Can't login?** Run this first:
```batch
diagnose_login_problems.bat
```

**Want to auto-fix common issues?** Run this:
```batch
quick_fix_login.bat
```

**Need to check user status?** Run this:
```batch
check_users.bat
```

---

## 📦 Tool Overview

### 1. diagnose_login_problems.bat
**Most comprehensive diagnostic tool**

**Checks 12 different areas:**
1. Docker service status
2. Auth service container health
3. MongoDB container status
4. Environment file existence
5. JWT secret configuration
6. JWT secret consistency across services
7. Port availability (3000)
8. Auth service health endpoint
9. MongoDB connectivity
10. Bridge/frontend configuration
11. Docker network setup
12. User database and verification status

**Output:**
- Color-coded console output
- Detailed report file: `login_diagnostic_report_YYYYMMDD_HHMMSS.txt`
- Issue count and severity levels
- Specific solutions for each problem found

**When to use:**
- Initial troubleshooting
- After deployment to new machine
- When login randomly stops working
- Before asking for help (run this first!)

---

### 2. quick_fix_login.bat
**Auto-fixes most common login issues**

**Performs these actions:**
1. Verifies admin user in database (sets isVerified=true)
2. Verifies admin@admin user if exists
3. Restarts auth-service container
4. Tests login endpoint with default credentials
5. Reports success or provides next steps

**When to use:**
- "Email not verified" errors
- After creating new users
- After container restarts
- As first quick fix attempt

**Safe to run:** Yes, doesn't modify passwords or delete data

---

### 3. check_users.bat
**Shows all users and their status**

**Displays:**
- Total user count
- Each user's username
- Each user's email
- Verification status (isVerified: true/false)
- User role (ADMIN, SUPERVISOR, USER)
- Special check for admin users

**When to use:**
- Verify users exist
- Check if user is verified
- See what username to use for login
- Before creating new admin user

---

## 🚦 Diagnostic Results Explained

### ✅ Green = OK
Everything is working correctly for this check.

### ⚠️ Yellow = Warning  
Not critical but may cause issues. System might still work.

### ❌ Red = Critical
WILL prevent login. Must be fixed.

---

## 🔍 Common Scenarios

### Scenario 1: Fresh Install / New Machine

```batch
REM 1. Check if everything is configured
diagnose_login_problems.bat

REM Expected issues:
REM - Docker not running
REM - No containers running
REM - No users in database

REM 2. Start Docker Desktop (manually)

REM 3. Start services
cd auth-service
start.bat

REM 4. Create admin user
cd quickCreateAdminPy
python create_admin.py

REM 5. Verify and test
cd ..\..
quick_fix_login.bat
```

---

### Scenario 2: Login Was Working, Now Broken

```batch
REM 1. Run diagnostics
diagnose_login_problems.bat

REM Look for recent changes:
REM - Container restarts?
REM - .env file changes?
REM - JWT secret changes?
REM - User deleted/modified?

REM 2. Try quick fix
quick_fix_login.bat

REM 3. Check user status
check_users.bat

REM 4. Check logs if still failing
docker logs auth-service --tail 50
```

---

### Scenario 3: Works on One Machine, Not Another

```batch
REM Run on BOTH machines:
diagnose_login_problems.bat

REM Compare the reports - likely differences:
REM - JWT secrets don't match
REM - Different Docker/container versions
REM - Port conflicts
REM - Firewall/antivirus blocking

REM Sync JWT secrets:
REM 1. On working machine, copy JWT secrets from auth-service\.env
REM 2. On broken machine, paste same secrets
REM 3. Restart: docker restart auth-service
```

---

### Scenario 4: "Authentication Failed" / JWT Errors

```batch
REM Most likely JWT secret mismatch or misconfiguration

REM 1. Run diagnostics
diagnose_login_problems.bat

REM Look for:
REM - "JWT_ACCESS_SECRET not properly configured"
REM - "JWT_REFRESH_SECRET mismatch between services"

REM 2. Fix secrets
generate_secrets.bat

REM 3. Restart all services
docker restart auth-service accounting-service flowise-proxy-service

REM 4. Clear browser cache
REM F12 > Console > localStorage.clear()

REM 5. Test login again
```

---

### Scenario 5: User Can't Login After System Restart

```batch
REM Common after PC restart or Docker restart

REM 1. Check containers are running
docker ps

REM If not running:
cd auth-service
start.bat

REM 2. Check user is still verified
check_users.bat

REM If not verified:
quick_fix_login.bat

REM 3. Test login
```

---

## 📊 Reading the Diagnostic Report

The report file contains:

### Section 1: Header
- Timestamp
- Machine name
- Workspace location

### Section 2: Test Results (1-12)
Each test shows:
- What was checked
- Status (OK/WARNING/CRITICAL)
- Specific error messages
- Solutions for failures

### Section 3: Additional Diagnostics
- Container status table
- Recent log entries from auth-service

### Section 4: Summary
- Total issues found
- Overall system health
- Common login problems checklist
- Quick fixes section

### Section 5: Quick Fixes
Detailed solutions for:
- Docker not running
- Containers not running
- JWT secrets
- User verification
- Database issues
- CORS errors
- Token problems

---

## 🛡️ What Each Tool Checks

### diagnose_login_problems.bat

| Check | What It Detects | How It Helps |
|-------|----------------|--------------|
| Docker Status | Docker Desktop running | Can't run containers without Docker |
| Auth Container | auth-service running | No auth = no login |
| MongoDB | Database accessible | Can't check users without DB |
| .env Files | Configuration exists | Missing config = failures |
| JWT Secrets | Secrets configured | No secrets = auth fails |
| JWT Consistency | Secrets match across services | Mismatch = token errors |
| Ports | 3000 listening | Service not accessible if port closed |
| Health Endpoint | Service responding | Basic connectivity check |
| DB Connection | MongoDB reachable | Can query users |
| Network | Docker network exists | Inter-service communication |
| Users | Admin exists & verified | Someone to login as |

### quick_fix_login.bat

| Action | Purpose | Safe? |
|--------|---------|-------|
| Update isVerified | Allow unverified users to login | ✅ Yes |
| Restart auth-service | Clear stuck state | ✅ Yes |
| Test login | Validate fix worked | ✅ Yes (read-only) |

### check_users.bat

| Output | Meaning |
|--------|---------|
| Total Users: 0 | No accounts exist - need to create |
| Total Users: 3 | 3 accounts exist |
| isVerified: false | User can't login - needs verification |
| isVerified: true | User can login |
| Role: ADMIN | Full system access |
| Role: USER | Limited access |

---

## 🎓 Understanding JWT Authentication

**Why JWT secrets matter so much:**

1. **Token Generation** (login)
   - User logs in → auth-service creates JWT token
   - Token is "signed" using JWT_ACCESS_SECRET
   - Like a digital signature that can't be forged

2. **Token Verification** (API requests)
   - User makes request → sends JWT token
   - Service verifies token using JWT_ACCESS_SECRET
   - If secret doesn't match → verification fails → rejected

3. **Multiple Services**
   - auth-service generates tokens
   - accounting-service verifies tokens
   - flowise-proxy verifies tokens
   - **All MUST use SAME secret**

**What happens when secrets don't match:**
```
User logs in → auth-service signs token with Secret A
User calls API → accounting-service tries to verify with Secret B
Result: "Invalid token" even though token is real!
```

This is why diagnose_login_problems.bat checks JWT consistency!

---

## 🔧 Advanced Usage

### Running on Remote Machine

```batch
REM Copy these files to target machine:
- diagnose_login_problems.bat
- quick_fix_login.bat  
- check_users.bat
- LOGIN_TROUBLESHOOTING_GUIDE.md

REM Run remotely:
diagnose_login_problems.bat

REM Review report and apply fixes
```

### Automated Monitoring

```batch
REM Create scheduled task:
schtasks /create /tn "Login Health Check" /tr "C:\path\to\diagnose_login_problems.bat" /sc daily /st 09:00

REM Or run in CI/CD:
diagnose_login_problems.bat
if %errorlevel% neq 0 (
    echo "Health check failed - alerting team"
)
```

### Batch Processing Multiple Issues

```batch
REM Check and fix in one go:
diagnose_login_problems.bat && quick_fix_login.bat && check_users.bat
```

---

## 📋 Pre-Deployment Checklist

Before deploying to a new machine, verify:

- [ ] Docker Desktop installed and running
- [ ] All .env files copied from reference machine
- [ ] JWT secrets match across all services
- [ ] Ports 3000, 3001, 27017, 5432, 8000 are available
- [ ] Run `diagnose_login_problems.bat` - 0 critical issues
- [ ] Run `check_users.bat` - admin user exists and verified
- [ ] Test login with browser
- [ ] Check browser console (F12) - no errors

---

## 🐛 Troubleshooting the Diagnostic Tools

### "Command not found" or syntax errors

**Solution:**
- Run from root workspace directory
- Use PowerShell or CMD (not Git Bash)
- Check file permissions

### "Docker not responding"

**Cause:** Docker Desktop not fully started yet

**Solution:**
- Wait 30 seconds after starting Docker Desktop
- Run `docker ps` to test
- Restart Docker Desktop if hung

### "Cannot connect to MongoDB"

**Cause:** MongoDB container not running

**Solution:**
```batch
cd auth-service
start.bat
timeout /t 10
docker ps | findstr mongodb
```

### Report file empty or incomplete

**Cause:** Script interrupted or permission issue

**Solution:**
- Run as Administrator
- Check disk space
- Run again (script is idempotent)

---

## 📞 Support Information

When asking for help, provide:

1. **Diagnostic report:**
   ```batch
   diagnose_login_problems.bat
   # Attach the generated .txt file
   ```

2. **Container logs:**
   ```batch
   docker logs auth-service > auth-logs.txt
   docker logs mongodb-auth > mongo-logs.txt
   ```

3. **Browser console errors:**
   - F12 → Console tab
   - Screenshot or copy errors

4. **System information:**
   - Windows version
   - Docker Desktop version
   - What was tried already

---

## 🎉 Success Indicators

Login system is healthy when:

✅ `diagnose_login_problems.bat` reports: **"No critical issues detected"**  
✅ All services show in `docker ps` with status "Up"  
✅ `check_users.bat` shows admin user with `isVerified: true`  
✅ Can access `http://localhost:3000/health`  
✅ Login form works in browser  
✅ Stay logged in after page refresh  
✅ No red errors in browser console (F12)

---

## 📚 Related Documentation

- **[LOGIN_TROUBLESHOOTING_GUIDE.md](LOGIN_TROUBLESHOOTING_GUIDE.md)** - Detailed solutions for every login problem
- **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** - Full deployment guide
- **[docs/JWT_AUTHENTICATION_FIXES.md](docs/JWT_AUTHENTICATION_FIXES.md)** - JWT-specific documentation

---

**Version:** 1.0  
**Compatible with:** Windows 10/11, Docker Desktop 4.x+  
**Last Updated:** March 3, 2026

---

## 💡 Pro Tips

1. **Run diagnostics FIRST** before making changes
2. **Save diagnostic reports** with timestamps for comparison
3. **One fix at a time** - don't stack changes
4. **Restart services** after environment variable changes
5. **Clear browser cache** after JWT secret changes
6. **Check logs** when diagnostics don't show obvious issues
7. **Use localhost** not 127.0.0.1 for URLs
8. **Keep JWT secrets secret** - don't commit to git

---

## Quick Reference Card

```
┌─────────────────────────────────────────────┐
│     UNIVERSAL LOGIN DIAGNOSTIC TOOLS        │
├─────────────────────────────────────────────┤
│                                             │
│  Can't Login?                               │
│  → diagnose_login_problems.bat              │
│                                             │
│  Quick Fix Needed?                          │
│  → quick_fix_login.bat                      │
│                                             │
│  Check Users?                               │
│  → check_users.bat                          │
│                                             │
│  Generate Secrets?                          │
│  → generate_secrets.bat                     │
│                                             │
│  View Logs?                                 │
│  → docker logs auth-service                 │
│                                             │
│  Emergency Reset?                           │
│  → See LOGIN_TROUBLESHOOTING_GUIDE.md       │
│     Section: Emergency Recovery             │
│                                             │
└─────────────────────────────────────────────┘
```
