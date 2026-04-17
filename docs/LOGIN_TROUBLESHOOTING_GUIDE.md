# Login & JWT Troubleshooting Guide

**Universal guide for diagnosing and fixing login problems on any Windows device**

---

## 🚀 Quick Start Diagnostic

Run this on any machine:
```batch
diagnose_login_problems.bat
```

This will automatically check all systems and generate a detailed report.

---

## 🔴 Common Login Problems & Solutions

### Problem 1: "Invalid credentials" Error

**Possible Causes:**
- Wrong username or password
- User account doesn't exist
- Username case sensitivity issues

**Solutions:**
```batch
# Check what users exist in database
check_users.bat

# Default credentials to try:
Username: admin
Password: admin

# Or try:
Username: admin@admin
Password: admin

# If no users exist, create admin:
cd auth-service\quickCreateAdminPy
python create_admin.py
```

**Additional Tips:**
- Try username in lowercase: `admin`
- Try email instead of username
- Password is case-sensitive

---

### Problem 2: "Email not verified" Error

**Cause:** User account exists but email is not verified

**Solutions:**
```batch
# Automatic fix - verifies all admin users:
quick_fix_login.bat

# Manual verification:
docker exec mongodb-auth mongosh --eval "use auth_db; db.users.updateOne({username:'admin'}, {$set:{isVerified:true}})"

# Check status:
check_users.bat
```

---

### Problem 3: JWT Token Errors / "Authentication failed"

**Possible Causes:**
- JWT secrets not configured
- JWT secrets mismatch across services  
- Old cached tokens in browser
- Token expired

**Detection:**
```batch
# Check JWT configuration:
diagnose_login_problems.bat

# Look for these warnings:
# - JWT_ACCESS_SECRET not properly configured
# - JWT_REFRESH_SECRET mismatch between services
```

**Solutions:**

#### Solution A: Generate and Sync JWT Secrets
```batch
# Run this to generate and sync secrets across all services:
generate_secrets.bat
```

#### Solution B: Manual JWT Secret Fix
1. Open `auth-service\.env`
2. Find these lines:
   ```
   JWT_ACCESS_SECRET=your_generated_access_secret_here
   JWT_REFRESH_SECRET=your_generated_refresh_secret_here
   ```
3. Copy EXACT same values to:
   - `accounting-service\.env`
   - `flowise-proxy-service-py\.env`
4. Restart all services:
   ```batch
   docker restart auth-service accounting-service flowise-proxy-service
   ```

#### Solution C: Clear Browser Cache
```javascript
// In browser console (F12):
localStorage.clear();
sessionStorage.clear();
// Then refresh page (Ctrl+F5)
```

**CRITICAL:** JWT secrets MUST be identical across all services!

---

### Problem 4: Login Successful but Immediately Logs Out

**Possible Causes:**
- Refresh token issues
- JWT_REFRESH_SECRET mismatch
- Cookie not being set/accepted
- Refresh token expired immediately

**Solutions:**

1. **Check JWT secrets match:**
   ```batch
   # Run diagnostic to verify:
   diagnose_login_problems.bat
   
   # Look for: "JWT secrets are consistent across services"
   ```

2. **Check refresh token settings in .env:**
   ```env
   JWT_REFRESH_SECRET=<same-as-access-secret>
   JWT_REFRESH_EXPIRES_IN=7d
   ```

3. **Check browser cookie settings:**
   - Ensure browser accepts cookies
   - Not in "Block all cookies" mode
   - Try different browser

4. **Check CORS configuration:**
   ```env
   # In auth-service\.env:
   CORS_ORIGIN=http://localhost:3082,http://localhost:8000
   CORS_CREDENTIALS=true
   ```

---

### Problem 5: Docker Not Running

**Symptoms:**
- Cannot connect to Docker
- "Docker daemon not running"

**Solutions:**
```batch
# 1. Start Docker Desktop from Windows Start Menu

# 2. Verify Docker is running:
docker ps

# 3. If command fails, restart Docker Desktop

# 4. Once running, start services:
cd auth-service
start.bat
```

---

### Problem 6: Auth Service Container Not Running

**Detection:**
```batch
docker ps -a | findstr auth-service
```

**Solutions:**
```batch
# Option 1: Use start script
cd auth-service
start.bat

# Option 2: Start manually
cd auth-service
docker-compose -f docker-compose.dev.yml up -d

# Option 3: Rebuild if corrupted
cd auth-service
rebuild.bat

# Verify it's running:
docker ps | findstr auth-service

# Check logs if failing:
docker logs auth-service --tail 50
```

---

### Problem 7: MongoDB Connection Failed

**Symptoms:**
- Auth service logs show "MongoDB connection error"
- Cannot query database

**Solutions:**
```batch
# Check if MongoDB is running:
docker ps | findstr mongodb

# Start MongoDB:
cd auth-service
start.bat

# Test connection:
docker exec mongodb-auth mongosh --eval "db.adminCommand('ping')"

# If connection fails, restart:
docker restart mongodb-auth

# Wait 10 seconds, then test again
```

---

### Problem 8: Port 3000 Already in Use

**Symptoms:**
- "Port 3000 is already allocated"
- Auth service won't start

**Solutions:**
```batch
# Find what's using port 3000:
netstat -ano | findstr :3000

# Kill the process (replace XXXX with PID from above):
taskkill /PID XXXX /F

# Or change port in auth-service\.env:
PORT=3001

# Then restart service
```

---

### Problem 9: CORS Errors in Browser

**Symptoms:**
- Browser console shows: "CORS policy blocked"
- Login request fails with CORS error
- Using wrong URL (127.0.0.1 instead of localhost)

**Solutions:**

1. **Check CORS configuration in auth-service\.env:**
   ```env
   CORS_ORIGIN=http://localhost:3082,http://localhost:8000
   CORS_CREDENTIALS=true
   ```

2. **Add your frontend URL if different:**
   ```env
   CORS_ORIGIN=http://localhost:3082,http://localhost:8000,http://192.168.1.100:3082
   ```

3. **Restart auth service after changes:**
   ```batch
   docker restart auth-service
   ```

4. **Access using localhost, not 127.0.0.1:**
   - ✅ Use: `http://localhost:3082`
   - ❌ Don't use: `http://127.0.0.1:3082`

---

### Problem 10: No Users in Database

**Symptoms:**
- check_users.bat shows "No users found"
- Fresh installation

**Solutions:**
```batch
# Option 1: Use Python script to create admin
cd auth-service\quickCreateAdminPy
python create_admin.py

# Option 2: Use signup endpoint
# POST to http://localhost:3000/api/auth/signup
# Body: {"username": "admin", "email": "admin@admin.com", "password": "admin"}

# Option 3: Direct database insert
docker exec mongodb-auth mongosh --eval "use auth_db; db.users.insertOne({username:'admin', email:'admin@admin.com', password:'$2b$10$...', isVerified:true, role:'ADMIN'})"

# Then verify user:
quick_fix_login.bat
```

---

### Problem 11: Health Endpoint Not Responding

**Symptoms:**
- `http://localhost:3000/health` returns error
- Service appears down

**Solutions:**
```batch
# Check if container is running:
docker ps | findstr auth-service

# Check container logs:
docker logs auth-service --tail 50

# Look for errors:
# - MongoDB connection failed
# - Port already in use
# - Environment variable missing

# Restart service:
docker restart auth-service

# Wait 10 seconds and test:
curl http://localhost:3000/health
```

---

## 🔍 Diagnostic Workflow

Follow this step-by-step process on any machine:

### Step 1: Run Full Diagnostics
```batch
diagnose_login_problems.bat
```
This generates a report file with all findings.

### Step 2: Check Infrastructure
```batch
# Verify Docker is running
docker ps

# Check service status
docker ps -a | findstr "auth-service\|mongodb-auth"

# Check ports
netstat -ano | findstr ":3000"
```

### Step 3: Check Configuration
```batch
# Verify .env files exist
dir auth-service\.env
dir accounting-service\.env

# Check JWT secrets are configured
findstr "JWT_ACCESS_SECRET" auth-service\.env
```

### Step 4: Check Database
```batch
# Check users exist and are verified
check_users.bat

# Test database connection
docker exec mongodb-auth mongosh --eval "db.adminCommand('ping')"
```

### Step 5: Test Endpoints
```powershell
# Test health endpoint
Invoke-RestMethod -Uri "http://localhost:3000/health"

# Test login endpoint
$body = @{username='admin'; password='admin'} | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:3000/api/auth/login" -Method Post -Body $body -ContentType 'application/json'
```

### Step 6: Check Browser
1. Open browser console (F12)
2. Go to login page
3. Attempt login
4. Check Console tab for errors
5. Check Network tab for failed requests
6. Check Application > Local Storage for old tokens

---

## 🛠️ Utility Scripts

### diagnose_login_problems.bat
**Purpose:** Comprehensive diagnostic for any Windows device  
**Usage:** `diagnose_login_problems.bat`  
**Output:** Detailed report file with all findings  

### quick_fix_login.bat  
**Purpose:** Auto-fix common issues  
**Usage:** `quick_fix_login.bat`  
**Actions:**
- Verifies admin users
- Restarts auth service
- Tests login endpoint

### check_users.bat
**Purpose:** Show all users and their verification status  
**Usage:** `check_users.bat`  
**Output:** List of users with verification and role info

### generate_secrets.bat
**Purpose:** Generate and sync JWT secrets across all services  
**Usage:** `generate_secrets.bat`  
**Critical:** Use this when JWT secrets are missing or mismatched

---

## 🔐 JWT Authentication Flow

Understanding the flow helps diagnose issues:

```
1. User submits login (username + password)
   ↓
2. Auth Service validates credentials
   ↓
3. Auth Service generates:
   - Access Token (JWT_ACCESS_SECRET, expires 1h)
   - Refresh Token (JWT_REFRESH_SECRET, expires 7d)
   ↓
4. Tokens sent to browser:
   - Access token in response body AND cookie
   - Refresh token in cookie only
   ↓
5. Browser stores tokens
   ↓
6. All API requests include access token
   ↓
7. Services verify token using JWT_ACCESS_SECRET
   ↓
8. If token expired, refresh using refresh token
   ↓
9. New access token generated using JWT_REFRESH_SECRET
```

**Key Points:**
- ALL services need the SAME JWT secrets
- Access token expires after 1 hour
- Refresh token expires after 7 days
- Token signature is checked on EVERY request
- If secrets don't match → Authentication fails

---

## 📋 Environment Variables Checklist

### auth-service/.env
```env
✅ PORT=3000
✅ NODE_ENV=development
✅ JWT_ACCESS_SECRET=<64-char-random-string>
✅ JWT_REFRESH_SECRET=<64-char-random-string>
✅ JWT_ACCESS_EXPIRES_IN=1h
✅ JWT_REFRESH_EXPIRES_IN=7d
✅ MONGODB_URI=mongodb://mongodb-auth:27017/auth_db
✅ CORS_ORIGIN=http://localhost:3082,http://localhost:8000
✅ CORS_CREDENTIALS=true
```

### accounting-service/.env
```env
✅ PORT=3001
✅ JWT_ACCESS_SECRET=<MUST-MATCH-AUTH-SERVICE>
✅ JWT_REFRESH_SECRET=<MUST-MATCH-AUTH-SERVICE>
```

### flowise-proxy-service-py/.env
```env
✅ JWT_ACCESS_SECRET=<MUST-MATCH-AUTH-SERVICE>
✅ JWT_REFRESH_SECRET=<MUST-MATCH-AUTH-SERVICE>
```

---

## 🌐 Network & Connectivity

### URLs to Use
- ✅ Frontend: `http://localhost:3082`
- ✅ Auth Service: `http://localhost:3000`
- ✅ Accounting: `http://localhost:3001`
- ✅ Flowise Proxy: `http://localhost:8000`

### URLs to AVOID
- ❌ Don't use: `http://127.0.0.1:3082` (causes CORS issues)
- ❌ Don't use: `http://0.0.0.0:3000` (not accessible)

---

## 🔥 Emergency Recovery

If nothing works, follow this sequence:

```batch
REM 1. Stop everything
docker-compose down
docker stop $(docker ps -aq)

REM 2. Clean up
docker system prune -f

REM 3. Regenerate secrets
generate_secrets.bat

REM 4. Start fresh
cd auth-service
start.bat

REM 5. Wait 30 seconds
timeout /t 30

REM 6. Verify services
docker ps

REM 7. Check logs
docker logs auth-service --tail 50
docker logs mongodb-auth --tail 50

REM 8. Create admin user
cd quickCreateAdminPy
python create_admin.py

REM 9. Verify user
cd ..\..
quick_fix_login.bat

REM 10. Test login
# Try logging in with: admin / admin
```

---

## 📞 Getting Help

If you've tried everything:

1. Run diagnostics and save output:
   ```batch
   diagnose_login_problems.bat
   ```

2. Collect logs:
   ```batch
   docker logs auth-service > auth-service-logs.txt
   docker logs mongodb-auth > mongodb-logs.txt
   ```

3. Check browser console (F12) and save errors

4. Provide:
   - Diagnostic report
   - Service logs  
   - Browser console errors
   - Steps you've already tried

---

## ✅ Success Criteria

You know login is working when:

- ✅ `diagnose_login_problems.bat` shows no critical issues
- ✅ `docker ps` shows auth-service and mongodb-auth running
- ✅ `http://localhost:3000/health` returns 200 OK
- ✅ `check_users.bat` shows users with `isVerified: true`
- ✅ Login in browser redirects to dashboard
- ✅ No errors in browser console
- ✅ User stays logged in after page refresh

---

**Last Updated:** March 3, 2026  
**Version:** 1.0  
**Platform:** Windows with Docker Desktop
