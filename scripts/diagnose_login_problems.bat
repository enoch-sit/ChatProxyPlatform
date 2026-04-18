@echo off
REM ============================================
REM Universal Login Problem Diagnostic Tool
REM ============================================
REM This script diagnoses common login issues including:
REM - Docker service status
REM - Container health  
REM - JWT configuration and mismatches
REM - Database connectivity
REM - Service availability
REM - Environment file validation
REM - User verification status
REM - CORS configuration
REM - Network connectivity
REM ============================================
REM Works on ANY Windows machine!
REM ============================================

setlocal enabledelayedexpansion

REM Set colors for output
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "CYAN=[96m"
set "MAGENTA=[95m"
set "RESET=[0m"

REM Get workspace directory (current directory)
set "WORKSPACE=%CD%"

echo.
echo %CYAN%============================================%RESET%
echo %CYAN%  UNIVERSAL LOGIN DIAGNOSTIC TOOL%RESET%
echo %CYAN%  Works on ANY Windows Device%RESET%
echo %CYAN%============================================%RESET%
echo Workspace: %WORKSPACE%
echo Timestamp: %DATE% %TIME%
echo Machine: %COMPUTERNAME%
echo User: %USERNAME%
echo.

REM Generate report filename with timestamp
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set "REPORT_FILE=login_diagnostic_report_%datetime:~0,8%_%datetime:~8,6%.txt"

echo Starting comprehensive login diagnostics...
echo Report will be saved to: %REPORT_FILE%
echo.

REM Initialize report
echo ============================================ > "%REPORT_FILE%"
echo   LOGIN PROBLEM DIAGNOSTIC REPORT >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"
echo Workspace: %WORKSPACE% >> "%REPORT_FILE%"
echo Timestamp: %DATE% %TIME% >> "%REPORT_FILE%"
echo. >> "%REPORT_FILE%"

set "ISSUES_FOUND=0"

REM ============================================
REM TEST 1: Check Docker Service Status
REM ============================================
echo %YELLOW%[1/12]%RESET% Checking Docker Service Status...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 1: Docker Service Status >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

docker --version >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] Docker is not installed or not in PATH%RESET%
    echo [CRITICAL] Docker is not installed or not in PATH >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    docker ps >nul 2>&1
    if !errorlevel! neq 0 (
        echo %RED%[✗] Docker Desktop is not running%RESET%
        echo [CRITICAL] Docker Desktop is not running >> "%REPORT_FILE%"
        echo   Solution: Start Docker Desktop >> "%REPORT_FILE%"
        set /a ISSUES_FOUND+=1
    ) else (
        echo %GREEN%[✓] Docker is running%RESET%
        echo [OK] Docker is running >> "%REPORT_FILE%"
    )
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 2: Check Auth Service Container
REM ============================================
echo %YELLOW%[2/12]%RESET% Checking Auth Service Container...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 2: Auth Service Container >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

docker ps -a --filter "name=auth-service" --format "{{.Names}}: {{.Status}}" >> "%REPORT_FILE%" 2>&1
docker ps --filter "name=auth-service" --filter "status=running" --format "{{.Names}}" | findstr "auth-service" >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] Auth service container is not running%RESET%
    echo [CRITICAL] Auth service container is not running >> "%REPORT_FILE%"
    echo   Solution: Run 'cd auth-service && start.bat' >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    echo %GREEN%[✓] Auth service container is running%RESET%
    echo [OK] Auth service container is running >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 3: Check MongoDB Container
REM ============================================
echo %YELLOW%[3/12]%RESET% Checking MongoDB Container...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 3: MongoDB Container >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

docker ps --filter "name=mongodb-auth" --filter "status=running" --format "{{.Names}}" | findstr "mongodb" >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] MongoDB container is not running%RESET%
    echo [CRITICAL] MongoDB container is not running >> "%REPORT_FILE%"
    echo   Solution: Run 'cd auth-service && start.bat' >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    echo %GREEN%[✓] MongoDB container is running%RESET%
    echo [OK] MongoDB container is running >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 4: Check Auth Service .env File
REM ============================================
echo %YELLOW%[4/12]%RESET% Checking Auth Service .env File...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 4: Auth Service .env File >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

if not exist "%WORKSPACE%\auth-service\.env" (
    echo %RED%[✗] Auth service .env file is missing%RESET%
    echo [CRITICAL] .env file not found at: auth-service\.env >> "%REPORT_FILE%"
    echo   Solution: Copy .env.example to .env and configure >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    echo %GREEN%[✓] Auth service .env file exists%RESET%
    echo [OK] .env file exists >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 5: Check JWT Secrets Configuration
REM ============================================
echo %YELLOW%[5/12]%RESET% Checking JWT Secrets...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 5: JWT Secrets Configuration >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

if exist "%WORKSPACE%\auth-service\.env" (
    findstr /C:"JWT_ACCESS_SECRET=" "%WORKSPACE%\auth-service\.env" | findstr /V "your_generated" >nul 2>&1
    if !errorlevel! neq 0 (
        echo %RED%[✗] JWT_ACCESS_SECRET not properly configured%RESET%
        echo [CRITICAL] JWT_ACCESS_SECRET is missing or using default value >> "%REPORT_FILE%"
        echo   Solution: Run generate_secrets.bat to generate secure secrets >> "%REPORT_FILE%"
        set /a ISSUES_FOUND+=1
    ) else (
        echo %GREEN%[✓] JWT_ACCESS_SECRET is configured%RESET%
        echo [OK] JWT_ACCESS_SECRET is configured >> "%REPORT_FILE%"
    )
    
    findstr /C:"JWT_REFRESH_SECRET=" "%WORKSPACE%\auth-service\.env" | findstr /V "your_generated" >nul 2>&1
    if !errorlevel! neq 0 (
        echo %RED%[✗] JWT_REFRESH_SECRET not properly configured%RESET%
        echo [CRITICAL] JWT_REFRESH_SECRET is missing or using default value >> "%REPORT_FILE%"
        echo   Solution: Run generate_secrets.bat to generate secure secrets >> "%REPORT_FILE%"
        set /a ISSUES_FOUND+=1
    ) else (
        echo %GREEN%[✓] JWT_REFRESH_SECRET is configured%RESET%
        echo [OK] JWT_REFRESH_SECRET is configured >> "%REPORT_FILE%"
    )
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 6: Check JWT Secrets Match Across Services
REM ============================================
echo %YELLOW%[6/12]%RESET% Checking JWT Secrets Consistency...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 6: JWT Secrets Consistency >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

set "JWT_MISMATCH=0"

if exist "%WORKSPACE%\auth-service\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" "%WORKSPACE%\auth-service\.env"') do set "AUTH_JWT_ACCESS=%%a"
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_REFRESH_SECRET=" "%WORKSPACE%\auth-service\.env"') do set "AUTH_JWT_REFRESH=%%a"
    
    if exist "%WORKSPACE%\accounting-service\.env" (
        for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" "%WORKSPACE%\accounting-service\.env"') do set "ACC_JWT_ACCESS=%%a"
        for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_REFRESH_SECRET=" "%WORKSPACE%\accounting-service\.env"') do set "ACC_JWT_REFRESH=%%a"
        
        if not "!AUTH_JWT_ACCESS!"=="!ACC_JWT_ACCESS!" (
            echo %RED%[✗] JWT_ACCESS_SECRET mismatch between auth-service and accounting-service%RESET%
            echo [CRITICAL] JWT_ACCESS_SECRET mismatch detected >> "%REPORT_FILE%"
            echo   Auth Service: !AUTH_JWT_ACCESS:~0,20!... >> "%REPORT_FILE%"
            echo   Accounting Service: !ACC_JWT_ACCESS:~0,20!... >> "%REPORT_FILE%"
            echo   Solution: Ensure all services use the same JWT secrets >> "%REPORT_FILE%"
            set "JWT_MISMATCH=1"
            set /a ISSUES_FOUND+=1
        )
        
        if not "!AUTH_JWT_REFRESH!"=="!ACC_JWT_REFRESH!" (
            echo %RED%[✗] JWT_REFRESH_SECRET mismatch between auth-service and accounting-service%RESET%
            echo [CRITICAL] JWT_REFRESH_SECRET mismatch detected >> "%REPORT_FILE%"
            echo   Solution: Ensure all services use the same JWT secrets >> "%REPORT_FILE%"
            set "JWT_MISMATCH=1"
            set /a ISSUES_FOUND+=1
        )
    )
    
    if exist "%WORKSPACE%\flowise-proxy-service-py\.env" (
        findstr /C:"JWT_ACCESS_SECRET=" "%WORKSPACE%\flowise-proxy-service-py\.env" >nul 2>&1
        if !errorlevel! equ 0 (
            for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" "%WORKSPACE%\flowise-proxy-service-py\.env"') do set "PROXY_JWT_ACCESS=%%a"
            
            if not "!AUTH_JWT_ACCESS!"=="!PROXY_JWT_ACCESS!" (
                echo %RED%[✗] JWT_ACCESS_SECRET mismatch with flowise-proxy-service%RESET%
                echo [CRITICAL] JWT_ACCESS_SECRET mismatch with flowise-proxy-service >> "%REPORT_FILE%"
                echo   Solution: Ensure all services use the same JWT secrets >> "%REPORT_FILE%"
                set "JWT_MISMATCH=1"
                set /a ISSUES_FOUND+=1
            )
        )
    )
)

if "%JWT_MISMATCH%"=="0" (
    echo %GREEN%[✓] JWT secrets are consistent across services%RESET%
    echo [OK] JWT secrets match across all services >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 7: Check Auth Service Port Availability
REM ============================================
echo %YELLOW%[7/12]%RESET% Checking Auth Service Port...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 7: Auth Service Port (3000) >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

netstat -ano | findstr ":3000" >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] Port 3000 is not listening%RESET%
    echo [WARNING] Port 3000 is not listening >> "%REPORT_FILE%"
    echo   Auth service may not be running >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    echo %GREEN%[✓] Port 3000 is listening%RESET%
    echo [OK] Port 3000 is listening >> "%REPORT_FILE%"
    netstat -ano | findstr ":3000" >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 8: Check Auth Service Health
REM ============================================
echo %YELLOW%[8/12]%RESET% Checking Auth Service Health Endpoint...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 8: Auth Service Health >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

powershell -Command "try { $response = Invoke-WebRequest -Uri 'http://localhost:3000/health' -UseBasicParsing -TimeoutSec 5; exit 0 } catch { exit 1 }" >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] Auth service health endpoint not responding%RESET%
    echo [CRITICAL] Health endpoint not responding at http://localhost:3000/health >> "%REPORT_FILE%"
    echo   Check container logs: docker logs auth-service >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    echo %GREEN%[✓] Auth service is responding%RESET%
    echo [OK] Health endpoint is responding >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 9: Check MongoDB Connection
REM ============================================
echo %YELLOW%[9/12]%RESET% Checking MongoDB Connection...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 9: MongoDB Connection >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

docker exec mongodb-auth mongosh --eval "db.adminCommand('ping')" >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] Cannot connect to MongoDB%RESET%
    echo [CRITICAL] Cannot connect to MongoDB container >> "%REPORT_FILE%"
    echo   Solution: Restart MongoDB container >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    echo %GREEN%[✓] MongoDB connection successful%RESET%
    echo [OK] MongoDB connection successful >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 10: Check Bridge Configuration
REM ============================================
echo %YELLOW%[10/12]%RESET% Checking Bridge (Frontend) Configuration...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 10: Bridge Configuration >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

if not exist "%WORKSPACE%\bridge\.env" (
    echo %YELLOW%[!] Bridge .env file is missing%RESET%
    echo [WARNING] Bridge .env file not found >> "%REPORT_FILE%"
    echo   Bridge may use default API URLs >> "%REPORT_FILE%"
    echo   Create .env with: VITE_FLOWISE_PROXY_API_URL=http://localhost:8000 >> "%REPORT_FILE%"
) else (
    echo %GREEN%[✓] Bridge .env file exists%RESET%
    echo [OK] Bridge .env file exists >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 11: Check Docker Network
REM ============================================
echo %YELLOW%[11/12]%RESET% Checking Docker Networks...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 11: Docker Networks >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

docker network ls | findstr "chatproxy-network" >nul 2>&1
if %errorlevel% neq 0 (
    echo %YELLOW%[!] chatproxy-network not found%RESET%
    echo [WARNING] chatproxy-network does not exist >> "%REPORT_FILE%"
    echo   This may cause service communication issues >> "%REPORT_FILE%"
) else (
    echo %GREEN%[✓] chatproxy-network exists%RESET%
    echo [OK] chatproxy-network exists >> "%REPORT_FILE%"
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM TEST 12: Check User Database
REM ============================================
echo %YELLOW%[12/12]%RESET% Checking User Database...
echo ============================================ >> "%REPORT_FILE%"
echo TEST 12: User Database >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.countDocuments()" >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] Cannot query user database%RESET%
    echo [CRITICAL] Cannot query user database >> "%REPORT_FILE%"
    set /a ISSUES_FOUND+=1
) else (
    for /f "delims=" %%i in ('docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.countDocuments()"') do set "USER_COUNT=%%i"
    if "!USER_COUNT!"=="" set "USER_COUNT=0"
    if "!USER_COUNT!"=="0" (
        echo %YELLOW%[!] No users found in database%RESET%
        echo [WARNING] No users found in database >> "%REPORT_FILE%"
        echo   Create admin user by running auth-service scripts >> "%REPORT_FILE%"
    ) else (
        echo %GREEN%[✓] Found !USER_COUNT! user^(s^) in database%RESET%
        echo [OK] Found !USER_COUNT! user(s) in database >> "%REPORT_FILE%"
        
        REM Check for admin users
        for /f "delims=" %%i in ('docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.countDocuments({username: 'admin'})"') do set "ADMIN_COUNT=%%i"
        if "!ADMIN_COUNT!"=="" set "ADMIN_COUNT=0"
        if "!ADMIN_COUNT!"=="0" (
            echo %YELLOW%[!] No admin user found%RESET%
            echo [WARNING] No user with username 'admin' found >> "%REPORT_FILE%"
        ) else (
            echo %GREEN%[✓] Admin user exists%RESET%
            echo [OK] Admin user exists >> "%REPORT_FILE%"
            
            REM Check if admin is verified
            docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.findOne({username: 'admin'}, {isVerified: 1})" 2>nul | findstr "isVerified: true" >nul 2>&1
            if !errorlevel! neq 0 (
                echo %RED%[✗] Admin user is not verified%RESET%
                echo [CRITICAL] Admin user email is not verified >> "%REPORT_FILE%"
                echo   Solution: Manually verify user or check email system >> "%REPORT_FILE%"
                set /a ISSUES_FOUND+=1
            ) else (
                echo %GREEN%[✓] Admin user is verified%RESET%
                echo [OK] Admin user is verified >> "%REPORT_FILE%"
            )
        )
    )
)
echo. >> "%REPORT_FILE%"

REM ============================================
REM ADDITIONAL DIAGNOSTICS
REM ============================================
echo ============================================ >> "%REPORT_FILE%"
echo ADDITIONAL DIAGNOSTICS >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"
 AND RECOMMENDATIONS
REM ============================================
echo.
echo %CYAN%============================================%RESET%
echo %CYAN%  DIAGNOSTIC SUMMARY%RESET%
echo %CYAN%============================================%RESET%
echo ============================================ >> "%REPORT_FILE%"
echo SUMMARY AND RECOMMENDATIONS >> "%REPORT_FILE%"
echo ============================================ >> "%REPORT_FILE%"

echo Total Issues Found: %ISSUES_FOUND%
echo Total Issues Found: %ISSUES_FOUND% >> "%REPORT_FILE%"
echo. >> "%REPORT_FILE%"

if %ISSUES_FOUND% equ 0 (
    echo %GREEN%[✓] No critical issues detected in infrastructure%RESET%
    echo [OK] No critical infrastructure issues detected >> "%REPORT_FILE%"
    echo.
    echo %YELLOW%If you still cannot login, check these common issues:%RESET%
    echo.
    echo %MAGENTA%COMMON LOGIN PROBLEMS:%RESET%
    echo   1. WRONG PASSWORD
    echo      - Default admin password is usually: admin
    echo      - Check if you changed the password
    echo.
    echo   2. USER NOT VERIFIED
    echo      - Check email for verification code
    echo      - Or manually verify: quick_fix_login.bat
    echo.
    echo   3. USERNAME CASE SENSITIVITY
    echo      - Try 'admin' (lowercase)
    echo      - Try 'Admin' (capitalized)
    echo      - Try the email address instead
    echo.
    echo   4. BROWSER/CACHE ISSUES
    echo      - Clear browser cache and cookies
    echo      - Try incognito/private mode
    echo      - Try a different browser
    echo.
    echo   5. NETWORK/CORS ISSUES
    echo      - Check browser console (F12) for CORS errors
    echo      - Verify you're using http://localhost:3082 (not 127.0.0.1)
    echo      - Check if firewall is blocking connections
    echo.
    echo   6. JWT TOKEN ISSUES
    echo      - Old tokens might be cached
    echo      - Clear localStorage in browser console
    echo      - Restart auth service: docker restart auth-service
    echo.
    echo. >> "%REPORT_FILE%"
    echo If login still fails after infrastructure checks pass: >> "%REPORT_FILE%"
    echo   1. Check browser console (F12) for JavaScript errors >> "%REPORT_FILE%"
    echo   2. Verify CORS configuration in auth-service/.env >> "%REPORT_FILE%"
    echo   3. Check network tab for 401/403 errors >> "%REPORT_FILE%"
    echo   4. Clear browser cache and localStorage >> "%REPORT_FILE%"
    echo   5. Try different username formats (admin vs email) >> "%REPORT_FILE%"
    echo   6. Run: check_users.bat to see user status >> "%REPORT_FILE%"
    echo   7. Run: quick_fix_login.bat to auto-verify users >> "%REPORT_FILE%"
) else (
    echo %RED%[!] Found %ISSUES_FOUND% infrastructure issue(s) that WILL prevent login%RESET%
    echo.
    echo [CRITICAL] Found %ISSUES_FOUND% infrastructure issue(s) >> "%REPORT_FILE%"
    echo.
    echo Please review the detailed report above for solutions.
    echo Key fixes are summarized in the QUICK FIXES section below.
    echo.
    echo. >> "%REPORT_FILE%"
)

echo Report saved to: %REPORT_FILE%
echo Full report saved to: %REPORT_FILE% >> "%REPORT_FILE%"
echo.
    echo %RED%[!] Found %ISSUES_FOUND% issue(s) that may prevent login%RESET%
    echo [CRITICAL] Found %ISSUES_FOUND% issue(s) >> "%REPORT_FILE%"
    ecCYAN%============================================%RESET%
echo %CYAN%  QUICK FIXES FOR COMMON ISSUES%RESET%
echo %CYAN%============================================%RESET%
echo.
echo %MAGENTA%ISSUE 1: Docker Not Running%RESET%
echo   Solution: Start Docker Desktop from Start Menu
echo   Verify: Run 'docker ps' to check
echo.
echo %MAGENTA%ISSUE 2: Containers Not Running%RESET%
echo   Solution: cd auth-service ^&^& start.bat
echo   Alternative: docker-compose up -d
echo   Verify: docker ps -a
echo.
echo %MAGENTA%ISSUE 3: JWT Secrets Not Configured%RESET%
echo   Solution: Run generate_secrets.bat in root folder
echo   Manual: Copy same JWT secrets to all service .env files
echo   Critical: Secrets MUST match in auth, accounting, flowise-proxy
echo.
echo %MAGENTA%ISSUE 4: JWT Secrets Mismatch%RESET%
echo   Problem: Different JWT secrets across services
echo   Solution: Run generate_secrets.bat to sync all services
echo   Manual: Copy from auth-service\.env to other services
echo   Restart: All services must restart after secret changes
echo.
echo %MAGENTA%ISSUE 5: User Not Verified%RESET%
echo   Solution: Run quick_fix_login.bat
echo   Manual: docker exec mongodb-auth mongosh --eval "use auth_db; db.users.updateOne({username:'admin'}, {$set:{isVerified:true}})"
echo   Check: Run check_users.bat
echo.
echo %MAGENTA%ISSUE 6: No Admin User Exists%RESET%
echo   Solution: cd auth-service\quickCreateAdminPy ^&^& python create_admin.py
echo   Alternative: Use signup endpoint to create first user
echo   Note: First user should be admin role
echo.
echo %MAGENTA%ISSUE 7: Database Connection Failed%RESET%
echo   Solution: Restart MongoDB: docker restart mongodb-auth
echo   Check logs: docker logs mongodb-auth
echo   Verify connection: docker exec mongodb-auth mongosh --eval "db.adminCommand('ping')"
echo.
echo %MAGENTA%ISSUE 8: Port Already in Use%RESET%
echo   Find process: netstat -ano ^| findstr :3000
echo   Kill process: taskkill /PID [PID_NUMBER] /F
echo   Or: Change PORT in .env file
echo.
echo %MAGENTA%ISSUE 9: CORS Errors in Browser%RESET%
echo   Check: Browser console (F12) for CORS messages
echo   Solution: Add frontend URL to CORS_ORIGIN in auth-service\.env
echo   Example: CORS_ORIGIN=http://localhost:3082,http://localhost:8000
echo   Restart: docker restart auth-service
echo.
echo %MAGENTA%ISSUE 10: Invalid Token / JWT Errors%RESET%
echo   Problem: Token signed with different secret or expired
echo   Solution 1: Clear browser localStorage and cookies
echo   Solution 2: Ensure JWT secrets match across all services
echo   Solution 3: Check JWT_ACCESS_EXPIRES_IN not too short
echo   Solution 4: Restart all services after secret changes
echo.
echo %MAGENTA%ISSUE 11: Login Works but Immediately Logs Out%RESET%
echo   Problem: Refresh token issues or cookie problems
echo   Solution 1: Check JWT_REFRESH_SECRET matches across services
echo   Solution 2: Verify refresh token endpoint working
echo   Solution 3: Check browser accepts cookies (not too strict)
echo.
echo %CYAN%============================================%RESET%
echo %CYAN%  GENERAL TROUBLESHOOTING WORKFLOW%RESET%
echo %CYAN%============================================%RESET%
echo.
echo 1. Start Docker Desktop
echo 2. cd auth-service ^&^& start.bat
echo 3. Wait 30 seconds for services to initialize
echo 4. Run: check_users.bat
echo 5. If no users exist: cd auth-service\quickCreateAdminPy ^&^& python create_admin.py
echo 6. If user not verified: quick_fix_login.bat
echo 7. Try login with: username=admin, password=admin
echo 8. Check browser console (F12) if still failing
echo 9. Check auth service logs: docker logs auth-service --tail 50
echo.
echo %YELLOW%For detailed diagnostics report, see: %REPORT_FILE%%RESET%
echo.
echo %GREEN%Need more help? Check these files:%RESET%
echo   - check_users.bat          : View all users and their status
echo   - quick_fix_login.bat      : Auto-fix common issues
echo   - generate_secrets.bat     : Generate and sync JWT secrets
echo   - auth-service\logs.bat    : View auth service logsIf containers are not running:
echo   cd auth-service
echo   start.bat
echo.
echo If JWT secrets are not configured:
echo   generate_secrets.bat
echo.
echo If admin user is not verified:
echo   cd auth-service\src\scripts
echo   node verify-user.js admin
echo.
echo.

pause
