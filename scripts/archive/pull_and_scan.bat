@echo off
REM ============================================================================
REM ChatProxyPlatform - Git Pull + Target Machine Scan
REM ============================================================================
REM Pulls latest code from git then scans the machine for:
REM   - Git status
REM   - Docker engine + required network
REM   - Running containers
REM   - Required ports
REM   - Environment (.env) files
REM   - Service health endpoints
REM ============================================================================

setlocal enabledelayedexpansion

title ChatProxy - Pull and Scan

REM ----------------------------------------------------------------------------
REM Log file setup
REM ----------------------------------------------------------------------------
set "TIMESTAMP=%DATE:~-4,4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TIMESTAMP=%TIMESTAMP: =0%"
set "LOGFILE=%~dp0pull_and_scan_%TIMESTAMP%.log"

echo.
echo ================================================================================
echo   ChatProxyPlatform - Pull and Scan
echo   Machine : %COMPUTERNAME%
echo   User    : %USERNAME%
echo   Date    : %DATE% %TIME%
echo   Log     : %LOGFILE%
echo ================================================================================
echo.

REM Ensure we run from the script directory
cd /d "%~dp0"

set PASS=0
set FAIL=0
set WARN=0
set FIX=0

REM ============================================================================
REM SECTION 1: GIT PULL
REM ============================================================================
echo ================================================================================
echo   SECTION 1: Git Pull
echo ================================================================================
echo.

git --version >nul 2>&1
if errorlevel 1 (
    call :warn "Git is NOT installed or not in PATH -- skipping git pull"
) else (
    echo [INFO] Checking git repository status...
    git status >nul 2>&1
    if errorlevel 1 (
        call :warn "Not inside a git repository -- skipping git pull"
    ) else (
        echo [INFO] Current branch:
        git branch --show-current
        echo.
        echo [INFO] Running git pull...
        git pull
        if errorlevel 1 (
            call :fail "git pull failed -- check credentials/network"
        ) else (
            call :pass "git pull completed successfully"
        )
    )
)
echo.

REM ============================================================================
REM SECTION 2: DOCKER ENGINE
REM ============================================================================
echo ================================================================================
echo   SECTION 2: Docker Engine
echo ================================================================================
echo.

echo [INFO] Checking Docker installation...
docker --version >nul 2>&1
if errorlevel 1 (
    call :fail "Docker is NOT installed or not in PATH"
    echo        Install Docker Desktop: https://www.docker.com/products/docker-desktop
    goto :docker_skip
)
for /f "tokens=*" %%v in ('docker --version 2^>^&1') do call :pass "%%v"

echo [INFO] Checking Docker daemon...
docker ps >nul 2>&1
if errorlevel 1 (
    call :fail "Docker daemon is NOT running -- please start Docker Desktop"
    goto :docker_skip
)
call :pass "Docker daemon is running"

echo [INFO] Docker compose version:
docker compose version 2>nul || docker-compose --version 2>nul
echo.

REM ============================================================================
REM SECTION 3: DOCKER NETWORK
REM ============================================================================
echo ================================================================================
echo   SECTION 3: Docker Network (chatproxy-network)
echo ================================================================================
echo.

echo [INFO] Listing existing Docker networks...
docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"
echo.

docker network inspect chatproxy-network >nul 2>&1
if errorlevel 1 (
    call :fail "chatproxy-network does NOT exist"
    echo.
    echo [FIX] Creating chatproxy-network...
    docker network create chatproxy-network
    if errorlevel 1 (
        call :fail "Failed to create chatproxy-network"
    ) else (
        call :pass "chatproxy-network created successfully"
        set /a FIX+=1
    )
) else (
    call :pass "chatproxy-network EXISTS"
    docker network inspect chatproxy-network --format "  Driver: {{.Driver}}  Scope: {{.Scope}}  Subnet: {{range .IPAM.Config}}{{.Subnet}}{{end}}"
)
echo.

REM ============================================================================
REM SECTION 4: RUNNING CONTAINERS
REM ============================================================================
echo ================================================================================
echo   SECTION 4: Running Containers
echo ================================================================================
echo.

echo [INFO] All containers (running + stopped):
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>nul
echo.

REM Check expected containers
set CONTAINERS=flowise auth-service accounting-service flowise-proxy-service
for %%c in (%CONTAINERS%) do (
    docker inspect %%c >nul 2>&1
    if errorlevel 1 (
        call :warn "Container '%%c' does not exist (not yet started)"
    ) else (
        for /f "tokens=*" %%s in ('docker inspect --format "{{.State.Status}}" %%c 2^>^&1') do (
            if "%%s"=="running" (
                call :pass "Container '%%c' is running"
            ) else (
                call :warn "Container '%%c' exists but status is: %%s"
            )
        )
    )
)
echo.

REM ============================================================================
REM SECTION 5: PORT AVAILABILITY
REM ============================================================================
echo ================================================================================
echo   SECTION 5: Port Availability
echo ================================================================================
echo.

REM Ports: auth=3000, accounting=3001, flowise=3002, flowise-proxy=8000, bridge=5173/80
set PORTS=3000 3001 3002 8000 5173
for %%p in (%PORTS%) do (
    netstat -an 2>nul | find "0.0.0.0:%%p " >nul 2>&1
    if not errorlevel 1 (
        call :pass "Port %%p is OPEN (something is listening)"
    ) else (
        netstat -an 2>nul | find ":::%%p " >nul 2>&1
        if not errorlevel 1 (
            call :pass "Port %%p is OPEN (something is listening)"
        ) else (
            call :warn "Port %%p is NOT in use (service may not be started)"
        )
    )
)
echo.

REM ============================================================================
REM SECTION 6: ENVIRONMENT FILES
REM ============================================================================
echo ================================================================================
echo   SECTION 6: Environment (.env) Files
echo ================================================================================
echo.

set ENV_PATHS=auth-service\.env accounting-service\.env flowise-proxy-service-py\.env flowise\.env
for %%e in (%ENV_PATHS%) do (
    if exist "%~dp0%%e" (
        call :pass ".env found: %%e"
    ) else (
        call :warn ".env MISSING: %%e  (copy from .env.example if available)"
    )
)
echo.

REM ============================================================================
REM SECTION 7: SERVICE HEALTH CHECKS (HTTP)
REM ============================================================================
echo ================================================================================
echo   SECTION 7: Service Health Checks
echo ================================================================================
echo.

REM Use curl if available
curl --version >nul 2>&1
if errorlevel 1 (
    call :warn "curl not found -- skipping HTTP health checks"
    goto :health_skip
)

set "HEALTH_ENDPOINTS=http://localhost:3000/health http://localhost:3001/health http://localhost:8000/health"
for %%u in (%HEALTH_ENDPOINTS%) do (
    echo [INFO] Checking %%u ...
    curl -s -o nul -w "  HTTP %%{http_code}" --max-time 5 %%u 2>nul
    echo.
    if errorlevel 1 (
        call :warn "No response from %%u"
    )
)

:health_skip
echo.

REM ============================================================================
REM SECTION 8: DISK SPACE
REM ============================================================================
echo ================================================================================
echo   SECTION 8: Disk Space
echo ================================================================================
echo.

for /f "tokens=1,2,3" %%a in ('wmic logicaldisk get DeviceID^,FreeSpace^,Size 2^>nul ^| findstr /r "[A-Z]:"') do (
    if not "%%b"=="" (
        set /a "FREE_GB=%%b/1073741824" 2>nul
        echo   Drive %%a  Free: !FREE_GB! GB
    )
)
echo.

REM ============================================================================
REM SUMMARY
REM ============================================================================
echo ================================================================================
echo   SCAN SUMMARY
echo ================================================================================
echo.
echo   Machine  : %COMPUTERNAME%
echo   User     : %USERNAME%
echo   PASS     : %PASS%
echo   FAIL     : %FAIL%
echo   WARNINGS : %WARN%
echo   AUTO-FIX : %FIX%
echo.

if %FAIL% GTR 0 (
    echo   [!!] %FAIL% issue(s) need attention before running setup.
) else (
    if %WARN% GTR 0 (
        echo   [OK] No hard failures found. Review %WARN% warning(s) above.
    ) else (
        echo   [OK] All checks passed. Machine looks ready.
    )
)
echo.
if %FIX% GTR 0 (
    echo   [FIX] %FIX% item(s) were automatically fixed (e.g. chatproxy-network created).
    echo         Re-run automated_setup.bat or your start scripts now.
    echo.
)

echo   Log saved to: %LOGFILE%
echo ================================================================================
echo.
pause
goto :eof

REM ============================================================================
REM Helper labels
REM ============================================================================
:pass
echo   [PASS] %~1
echo [PASS] %~1 >> "%LOGFILE%"
set /a PASS+=1
goto :eof

:fail
echo   [FAIL] %~1
echo [FAIL] %~1 >> "%LOGFILE%"
set /a FAIL+=1
goto :eof

:warn
echo   [WARN] %~1
echo [WARN] %~1 >> "%LOGFILE%"
set /a WARN+=1
goto :eof

:docker_skip
echo   [INFO] Skipping Docker-dependent checks.
echo.
goto :eof
