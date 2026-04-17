# Testing the Automated Setup - Quick Guide

## 🧹 How to Clean Up for Fresh Test

### Step 1: Run the Cleanup Script
```cmd
cleanup_for_fresh_setup.bat
```

**What it does**:
- ✅ Stops all services (Flowise, Auth, Accounting, Proxy, Bridge)
- ✅ Removes all Docker containers
- ✅ Deletes all Docker volumes ⚠️ **DATA LOSS**
  - MongoDB databases (users, sessions)
  - PostgreSQL databases (credits, accounting)
  - Flowise data
- ✅ Removes chatproxy-network
- ✅ Cleans node_modules (optional)

**Confirmation Required**: You'll be asked to type "yes" to confirm

---

## 🚀 Step 2: Test the Automated Setup

After cleanup, run:
```cmd
automated_setup.bat
```

**Expected Flow**:
1. System scan (~30 seconds)
   - Checks Docker, Python, Git
   - Detects drives and selects optimal one
   
2. Volume configuration (~10 seconds)
   - Updates docker-compose files
   - Creates volume directories

3. Starts Flowise (~2 minutes)
   - Waits for health check
   - Should show success message

4. **Prompts for Flowise API key** ⚠️ **USER INPUT NEEDED**
   - Open http://localhost:3002
   - Login or create account
   - Go to Settings → API Keys
   - Create key and paste it

5. Service configuration (~5 seconds)
   - Syncs JWT secrets
   - Updates all .env files

6. Starts auth service (~1 minute)
   - npm install if needed
   - Docker compose up

7. Starts accounting service (~1 minute)
   - npm install if needed
   - Docker compose up

8. Creates admin user (~30 seconds)
   - Registers admin
   - Verifies email
   - Tests login
   - Allocates 10,000 credits

9. Creates additional users (~2 minutes)
   - 3 teachers: 5,000 credits each
   - 5 students: 1,000 credits each

10. Starts flowise proxy (~1 minute)
    - Docker compose up

11. Starts bridge UI (~1 minute)
    - npm install if needed
    - Docker compose up

12. System verification (~30 seconds)
    - Tests all endpoints
    - Verifies authentication
    - Checks credit balance

13. Success message! 🎉
    - Shows next steps
    - Displays access URL

**Total Time**: 10-15 minutes

---

## ✅ Verification Checklist

After automated_setup.bat completes, verify:

### 1. All Containers Running
```cmd
docker ps
```
Expected: 9 containers running
- flowise
- flowise-postgres
- auth-service
- mongodb-auth
- auth-mailhog
- accounting-service
- postgres-accounting
- flowise-proxy
- mongodb-proxy
- bridge-ui

### 2. Bridge UI Accessible
Open browser: http://localhost:3082

### 3. Admin Login Works
- Username: `admin`
- Password: `admin@admin`

### 4. Credits Display
Should show: **10,000 credits**

### 5. Other Users Created
```powershell
# Check via API
$auth = Invoke-RestMethod -Uri "http://localhost:8000/api/v1/chat/authenticate" -Method POST -ContentType "application/json" -Body '{"username":"teacher1","password":"admin@admin"}'
Invoke-RestMethod -Uri "http://localhost:8000/api/v1/chat/credits" -Headers @{Authorization = "Bearer $($auth.access_token)"}
```
Expected: 5,000 credits for teachers, 1,000 for students

---

## 🐛 If Automated Setup Fails

### Check Script Output
The script shows detailed progress. Look for error messages.

### Common Issues

#### 1. Docker Not Running
**Error**: "Docker daemon is not running"
**Fix**: Start Docker Desktop

#### 2. Flowise Won't Start
**Error**: Timeout waiting for Flowise
**Fix**: Check logs:
```cmd
cd flowise
docker-compose logs -f
```

#### 3. API Key Prompt Timeout
**Issue**: User takes too long to get API key
**Fix**: Script waits indefinitely for input, just take your time

#### 4. Port Already in Use
**Error**: "port is already allocated"
**Fix**: Run cleanup_for_fresh_setup.bat again

### Manual Verification

Check each service:
```cmd
# Flowise
curl http://localhost:3002/api/v1/health

# Auth
curl http://localhost:3000/health

# Accounting
curl http://localhost:3001/health

# Proxy
curl http://localhost:8000/health

# Bridge
curl http://localhost:3082
```

---

## 🔄 Testing Multiple Times

### Quick Cleanup + Test Cycle
```cmd
cleanup_for_fresh_setup.bat
# Wait for cleanup to finish
automated_setup.bat
```

### For Fast Iteration (Keep Flowise API Key)

If you want to test repeatedly without re-entering the API key:

1. First run: Complete setup and note your API key
2. Edit `automated_setup.py` temporarily:
   ```python
   def get_flowise_api_key() -> str:
       # For testing - hardcode your key
       return "your_api_key_here"
   ```
3. Run cleanup and setup again
4. **Remember to remove hardcoded key before committing!**

---

## 📊 What to Look For

### Successful Setup Indicators
- ✅ All steps show green checkmarks
- ✅ No red error messages
- ✅ "Setup Complete!" message displays
- ✅ Bridge UI accessible
- ✅ Admin can login
- ✅ Credits show 10,000

### Failure Indicators
- ❌ Red error messages
- ❌ Script exits early
- ❌ Services won't start
- ❌ Cannot access Bridge UI
- ❌ Login fails
- ❌ Credits show 0 or error

---

## 📝 Report Issues

If automated setup fails, please document:

1. **Error message** - Exact text from script
2. **Step failed** - Which step (1-13) failed
3. **System info**:
   ```cmd
   docker --version
   python --version
   echo %USERPROFILE%
   ```
4. **Docker status**:
   ```cmd
   docker ps -a
   ```
5. **Drive space**:
   ```cmd
   wmic logicaldisk get name,freespace,size
   ```

---

## 🎯 Success Criteria

Your automated setup is working correctly if:

1. ✅ Cleanup script removes everything
2. ✅ Automated setup completes without errors
3. ✅ All 9 containers running
4. ✅ Bridge UI loads
5. ✅ Admin can login
6. ✅ Admin has 10,000 credits
7. ✅ Total time: 10-15 minutes
8. ✅ Only 1 user input (API key)

---

## 💡 Pro Tips

### Save Your API Key
After first setup, save your Flowise API key somewhere safe for future tests.

### Use Docker Desktop UI
Open Docker Desktop → Containers to visually see services starting.

### Monitor Logs
In separate terminals, you can watch logs:
```cmd
# Terminal 1
cd flowise
docker-compose logs -f

# Terminal 2
cd auth-service
docker-compose logs -f
```

### Take Screenshots
Document the success for your pull request!

---

## 🎉 After Successful Test

You can confidently:
1. Create the pull request
2. Show it works end-to-end
3. Include test results in PR description
4. Help others who want to use it

---

**Happy Testing!** 🚀
