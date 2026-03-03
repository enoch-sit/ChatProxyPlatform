@echo off
REM ============================================
REM Quick Login Problem Fix Script
REM ============================================
REM This script attempts to automatically fix common login issues
REM ============================================

setlocal enabledelayedexpansion

set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "RESET=[0m"

echo.
echo %BLUE%============================================%RESET%
echo %BLUE%  QUICK LOGIN PROBLEM FIX%RESET%
echo %BLUE%============================================%RESET%
echo.

REM ============================================
REM FIX 1: Verify Admin User
REM ============================================
echo %YELLOW%[1/3]%RESET% Verifying admin user in database...

docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.updateOne({username: 'admin'}, {$set: {isVerified: true}})" >nul 2>&1
if %errorlevel% equ 0 (
    echo %GREEN%[✓] Admin user verified%RESET%
) else (
    echo %RED%[✗] Could not verify admin user (MongoDB may not be running)%RESET%
)

REM Also try admin@admin
docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.updateOne({username: 'admin@admin'}, {$set: {isVerified: true}})" >nul 2>&1

REM ============================================
REM FIX 2: Restart Auth Service
REM ============================================
echo %YELLOW%[2/3]%RESET% Restarting auth service...

docker restart auth-service >nul 2>&1
if %errorlevel% equ 0 (
    echo %GREEN%[✓] Auth service restarted%RESET%
    echo Waiting for service to be ready...
    timeout /t 5 /nobreak >nul
) else (
    echo %RED%[✗] Could not restart auth service%RESET%
)

REM ============================================
REM FIX 3: Test Login
REM ============================================
echo %YELLOW%[3/3]%RESET% Testing login endpoint...

powershell -Command "$body = @{username='admin'; password='admin'} | ConvertTo-Json; try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/auth/login' -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 5; Write-Host 'Login successful!'; exit 0 } catch { Write-Host 'Login failed:' $_.Exception.Message; exit 1 }" 
if %errorlevel% equ 0 (
    echo %GREEN%[✓] Login test successful%RESET%
) else (
    echo %RED%[✗] Login test failed%RESET%
    echo.
    echo Possible issues:
    echo   1. Wrong password for admin user
    echo   2. Auth service not ready yet
    echo   3. User doesn't exist in database
    echo.
    echo Try creating a new admin user:
    echo   cd auth-service\quickCreateAdminPy
    echo   python create_admin.py
)

echo.
echo %BLUE%============================================%RESET%
echo Done! Try logging in again.
echo.
echo If issues persist:
echo   1. Run diagnose_login_problems.bat for full diagnostics
echo   2. Check auth-service logs: docker logs auth-service
echo   3. Create new admin user: cd auth-service\quickCreateAdminPy
echo %BLUE%============================================%RESET%
echo.

pause
