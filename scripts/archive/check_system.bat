@echo off
REM ============================================
REM System Check - ChatProxy Platform
REM ============================================
REM Checks all prerequisites and system status
REM for non-technical users

setlocal enabledelayedexpansion

echo.
echo ============================================
echo   ChatProxy Platform - System Check
echo ============================================
echo.

REM Initialize counters
set PASSED=0
set FAILED=0
set WARNINGS=0

REM ============================================
REM Phase 1: Check Prerequisites
REM ============================================

echo [Phase 1: Checking Prerequisites]
echo.

REM Check 1: Docker
echo Checking Docker...
docker --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [32m[PASS][0m Docker is installed
    for /f "tokens=3" %%a in ('docker --version') do set DOCKER_VER=%%a
    echo       Version: !DOCKER_VER!
    set /a PASSED+=1
) else (
    echo [31m[FAIL][0m Docker is NOT installed
    echo       Install from: https://www.docker.com/products/docker-desktop
    set /a FAILED+=1
)
echo.

REM Check 2: Docker running
echo Checking if Docker is running...
docker ps >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [32m[PASS][0m Docker Desktop is running
    set /a PASSED+=1
) else (
    echo [31m[FAIL][0m Docker Desktop is NOT running
    echo       Please start Docker Desktop and try again
    set /a FAILED+=1
)
echo.

REM Check 3: Python
echo Checking Python...
python --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [32m[PASS][0m Python is installed
    for /f "tokens=2" %%a in ('python --version') do set PYTHON_VER=%%a
    echo       Version: !PYTHON_VER!
    set /a PASSED+=1
) else (
    echo [31m[FAIL][0m Python is NOT installed
    echo       Install from: https://www.python.org/downloads/
    echo       IMPORTANT: Check "Add Python to PATH" during installation
    set /a FAILED+=1
)
echo.

REM Check 4: Git (optional)
echo Checking Git (optional)...
git --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [32m[PASS][0m Git is installed
    for /f "tokens=3" %%a in ('git --version') do set GIT_VER=%%a
    echo       Version: !GIT_VER!
    set /a PASSED+=1
) else (
    echo [33m[WARN][0m Git is NOT installed (optional)
    echo       Recommended: https://git-scm.com/download/win
    set /a WARNINGS+=1
)
echo.

REM ============================================
REM Phase 2: Check Port Availability
REM ============================================

echo [Phase 2: Checking Port Availability]
echo.

REM Check ports
set PORTS=3000 3001 3002 3082 8000
for %%p in (%PORTS%) do (
    echo Checking port %%p...
    netstat -ano | findstr :%%p >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo [33m[WARN][0m Port %%p is in use
        echo       Service may already be running or blocked
        set /a WARNINGS+=1
    ) else (
        echo [32m[PASS][0m Port %%p is available
        set /a PASSED+=1
    )
)
echo.

REM ============================================
REM Phase 3: Check Disk Space
REM ============================================

echo [Phase 3: Checking Disk Space]
echo.

REM Get free space on C: drive
for /f "tokens=3" %%a in ('dir C:\ ^| findstr /C:"bytes free"') do set FREE_SPACE=%%a
REM Convert to GB (divide by 1073741824)
set /a FREE_GB=!FREE_SPACE:~0,-10!

echo Checking available disk space...
if !FREE_GB! GEQ 5 (
    echo [32m[PASS][0m Sufficient disk space: ~!FREE_GB! GB free
    set /a PASSED+=1
) else (
    echo [31m[FAIL][0m Insufficient disk space: ~!FREE_GB! GB free
    echo       Need at least 5 GB free space
    echo       Please free up disk space and try again
    set /a FAILED+=1
)
echo.

REM ============================================
REM Phase 4: Check Docker Services
REM ============================================

echo [Phase 4: Checking Docker Services]
echo.

REM Check if services are running
set SERVICES=flowise auth-service accounting-service flowise-proxy bridge-ui

for %%s in (%SERVICES%) do (
    echo Checking %%s...
    docker ps --format "{{.Names}}" | findstr /C:"%%s" >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo [32m[PASS][0m %%s is running
        set /a PASSED+=1
    ) else (
        echo [33m[WARN][0m %%s is NOT running
        echo       Run: cd %%s ^& start.bat
        set /a WARNINGS+=1
    )
)
echo.

REM ============================================
REM Phase 5: Check Configuration Files
REM ============================================

echo [Phase 5: Checking Configuration Files]
echo.

REM Check users.csv
echo Checking users.csv...
if exist "auth-service\quickCreateAdminPy\users.csv" (
    echo [32m[PASS][0m users.csv exists
    REM Count lines in CSV (excluding header)
    set COUNT=0
    for /f "skip=1" %%a in (auth-service\quickCreateAdminPy\users.csv) do set /a COUNT+=1
    echo       Users defined: !COUNT!
    set /a PASSED+=1
) else (
    echo [31m[FAIL][0m users.csv NOT found
    echo       Expected at: auth-service\quickCreateAdminPy\users.csv
    set /a FAILED+=1
)
echo.

REM Check Flowise API Key
echo Checking Flowise API key configuration...
if exist "flowise-proxy-service-py\.env" (
    findstr /C:"FLOWISE_API_KEY=" flowise-proxy-service-py\.env | findstr /V /C:"FLOWISE_API_KEY=$" >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo [32m[PASS][0m Flowise API key is configured
        set /a PASSED+=1
    ) else (
        echo [33m[WARN][0m Flowise API key NOT configured
        echo       Generate key in Flowise UI and add to .env
        set /a WARNINGS+=1
    )
) else (
    echo [31m[FAIL][0m flowise-proxy-service-py\.env NOT found
    set /a FAILED+=1
)
echo.

REM ============================================
REM Phase 6: Check API Endpoints
REM ============================================

echo [Phase 6: Checking API Endpoints]
echo.

REM Check if curl is available
where curl >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    REM Test Auth Service
    echo Testing Auth Service API...
    curl -s http://localhost:3000/health >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo [32m[PASS][0m Auth Service is responding
        set /a PASSED+=1
    ) else (
        echo [33m[WARN][0m Auth Service not responding
        set /a WARNINGS+=1
    )
    
    REM Test Flowise
    echo Testing Flowise API...
    curl -s http://localhost:3002 >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo [32m[PASS][0m Flowise is responding
        set /a PASSED+=1
    ) else (
        echo [33m[WARN][0m Flowise not responding
        set /a WARNINGS+=1
    )
    
    REM Test Bridge UI
    echo Testing Bridge UI...
    curl -s http://localhost:3082 >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo [32m[PASS][0m Bridge UI is responding
        set /a PASSED+=1
    ) else (
        echo [33m[WARN][0m Bridge UI not responding
        set /a WARNINGS+=1
    )
) else (
    echo [33m[WARN][0m curl not available - skipping API tests
    set /a WARNINGS+=1
)
echo.

REM ============================================
REM Summary
REM ============================================

echo.
echo ============================================
echo   System Check Summary
echo ============================================
echo.
echo [32mPassed:[0m  !PASSED! checks
echo [33mWarnings:[0m !WARNINGS! issues
echo [31mFailed:[0m  !FAILED! critical issues
echo.

if !FAILED! EQU 0 (
    if !WARNINGS! EQU 0 (
        echo [32m[SUCCESS][0m System is ready for deployment!
        echo.
        echo Next steps:
        echo 1. Start all services: start_all_services.bat
        echo 2. Follow DEPLOYMENT_PLAN.md
    ) else (
        echo [33m[CAUTION][0m System is mostly ready, but has some warnings
        echo.
        echo Review warnings above and consider fixing them
        echo You can proceed with deployment, but some features may not work
    )
) else (
    echo [31m[ERROR][0m System is NOT ready for deployment
    echo.
    echo Please fix the failed checks above before proceeding
    echo.
    echo Common solutions:
    echo - Install Docker Desktop from https://www.docker.com
    echo - Install Python from https://www.python.org
    echo - Start Docker Desktop
    echo - Free up disk space (need 5+ GB)
)

echo.
echo ============================================
echo.

REM ============================================
REM Generate detailed report
REM ============================================

echo Generating detailed report...
set REPORT_FILE=system_check_report_%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%.txt
set REPORT_FILE=%REPORT_FILE: =0%

(
    echo ChatProxy Platform - System Check Report
    echo ========================================
    echo.
    echo Date: %date% %time%
    echo Computer: %COMPUTERNAME%
    echo User: %USERNAME%
    echo.
    echo Summary:
    echo   Passed:   !PASSED!
    echo   Warnings: !WARNINGS!
    echo   Failed:   !FAILED!
    echo.
    echo Details:
    docker --version 2>&1
    python --version 2>&1
    git --version 2>&1
    echo.
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>&1
    echo.
    netstat -ano | findstr ":3000 :3001 :3002 :3082 :8000" 2>&1
) > %REPORT_FILE%

echo Report saved to: %REPORT_FILE%
echo.

pause
