@echo off
REM ============================================================
REM  update_patch.bat — Pull latest changes and redeploy services
REM ============================================================
REM  Usage:
REM    update_patch.bat          — prompts for Quick or Full mode
REM    update_patch.bat quick    — recreate containers only (env changes)
REM    update_patch.bat full     — rebuild images + recreate (code changes)
REM ============================================================

setlocal enabledelayedexpansion

set "GREEN=[92m"
set "YELLOW=[93m"
set "RED=[91m"
set "BLUE=[94m"
set "CYAN=[96m"
set "RESET=[0m"

set "MODE=%~1"

echo.
echo %BLUE%============================================================%RESET%
echo %BLUE%   ChatProxyPlatform — Update and Patch Script%RESET%
echo %BLUE%============================================================%RESET%
echo.

REM ─────────────────────────────────────────────────────────────
REM Step 0: Verify Docker is running
REM ─────────────────────────────────────────────────────────────
echo %CYAN%[0/5]%RESET% Checking Docker...
docker info >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[X] Docker is not running. Please start Docker Desktop first.%RESET%
    pause
    exit /b 1
)
echo %GREEN%[OK] Docker is running.%RESET%
echo.

REM ─────────────────────────────────────────────────────────────
REM Step 1: Git pull
REM ─────────────────────────────────────────────────────────────
echo %CYAN%[1/5]%RESET% Pulling latest changes from git...
git pull
if %errorlevel% neq 0 (
    echo %RED%[X] git pull failed. Resolve conflicts or network issues and retry.%RESET%
    pause
    exit /b 1
)
echo %GREEN%[OK] Git pull complete.%RESET%
echo.

REM ─────────────────────────────────────────────────────────────
REM Step 2: Update .env files
REM ─────────────────────────────────────────────────────────────
echo %CYAN%[2/5]%RESET% Updating .env files via automated_setup.py...
python automated_setup.py
if %errorlevel% neq 0 (
    echo %YELLOW%[WARN] automated_setup.py reported an error. Continuing with existing .env files.%RESET%
) else (
    echo %GREEN%[OK] .env files updated.%RESET%
)
echo.

REM ─────────────────────────────────────────────────────────────
REM Step 3: Choose mode
REM ─────────────────────────────────────────────────────────────
if /i "%MODE%"=="quick" goto :do_quick
if /i "%MODE%"=="full"  goto :do_full

echo %CYAN%[3/5]%RESET% Choose deployment mode:
echo.
echo   %YELLOW%[1] Quick%RESET%  — Recreate containers only (fast, picks up env/config changes)
echo   %YELLOW%[2] Full%RESET%   — Rebuild images + recreate (required after code changes)
echo.
set /p "CHOICE=Enter choice (1 or 2, default=1): "
if "%CHOICE%"=="2" goto :do_full
goto :do_quick

REM ─────────────────────────────────────────────────────────────
REM QUICK MODE: force-recreate without rebuilding images
REM ─────────────────────────────────────────────────────────────
:do_quick
echo.
echo %BLUE%[MODE] Quick — recreating containers (no image rebuild)%RESET%
echo.
goto :deploy

REM ─────────────────────────────────────────────────────────────
REM FULL MODE: rebuild images then recreate
REM ─────────────────────────────────────────────────────────────
:do_full
echo.
echo %BLUE%[MODE] Full — rebuilding images and recreating containers%RESET%
echo.
set "BUILD_FLAG=--build"
goto :deploy

REM ─────────────────────────────────────────────────────────────
REM Step 4: Redeploy services in dependency order
REM ─────────────────────────────────────────────────────────────
:deploy
echo %CYAN%[4/5]%RESET% Redeploying services...
echo.

set "ERRORS=0"

REM --- auth-service (mongodb-auth depends on it) ---
echo %YELLOW%>> auth-service%RESET%
cd "%~dp0auth-service"
docker compose -f docker-compose.dev.yml up -d --force-recreate %BUILD_FLAG% auth-service
if %errorlevel% neq 0 (
    echo %RED%   [X] auth-service failed%RESET%
    set "ERRORS=1"
) else (
    echo %GREEN%   [OK] auth-service started%RESET%
)
echo.

REM --- accounting-service ---
echo %YELLOW%>> accounting-service%RESET%
cd "%~dp0accounting-service"
docker compose up -d --force-recreate %BUILD_FLAG% accounting-service
if %errorlevel% neq 0 (
    echo %RED%   [X] accounting-service failed%RESET%
    set "ERRORS=1"
) else (
    echo %GREEN%   [OK] accounting-service started%RESET%
)
echo.

REM --- flowise ---
echo %YELLOW%>> flowise%RESET%
cd "%~dp0flowise"
docker compose up -d --force-recreate %BUILD_FLAG%
if %errorlevel% neq 0 (
    echo %RED%   [X] flowise failed%RESET%
    set "ERRORS=1"
) else (
    echo %GREEN%   [OK] flowise started%RESET%
)
echo.

REM --- flowise-proxy (depends on auth + accounting) ---
echo %YELLOW%>> flowise-proxy%RESET%
cd "%~dp0flowise-proxy-service-py"
docker compose up -d --force-recreate --no-deps %BUILD_FLAG% flowise-proxy
if %errorlevel% neq 0 (
    echo %RED%   [X] flowise-proxy failed%RESET%
    set "ERRORS=1"
) else (
    echo %GREEN%   [OK] flowise-proxy started%RESET%
)
echo.

REM --- bridge (frontend, depends on proxy being up) ---
echo %YELLOW%>> bridge-ui%RESET%
cd "%~dp0bridge"
docker compose up -d --force-recreate %BUILD_FLAG%
if %errorlevel% neq 0 (
    echo %RED%   [X] bridge-ui failed%RESET%
    set "ERRORS=1"
) else (
    echo %GREEN%   [OK] bridge-ui started%RESET%
)
echo.

REM ─────────────────────────────────────────────────────────────
REM Step 5: Summary
REM ─────────────────────────────────────────────────────────────
cd "%~dp0"
echo %CYAN%[5/5]%RESET% Container status:
echo.
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=auth-service" --filter "name=accounting-service" --filter "name=flowise-proxy" --filter "name=flowise" --filter "name=bridge-ui"

echo.
if "%ERRORS%"=="0" (
    echo %GREEN%============================================================%RESET%
    echo %GREEN%   All services updated successfully!%RESET%
    echo %GREEN%============================================================%RESET%
) else (
    echo %RED%============================================================%RESET%
    echo %RED%   One or more services failed to start. Check logs above.%RESET%
    echo %RED%============================================================%RESET%
    echo.
    echo Useful commands:
    echo   docker logs flowise-proxy --tail=50
    echo   docker logs auth-service --tail=50
    echo   docker logs accounting-service --tail=50
)
echo.
echo Service URLs:
echo   Bridge UI   : http://localhost:3082
echo   Flowise     : http://localhost:3002
echo   Proxy API   : http://localhost:8000
echo   Auth API    : http://localhost:3000
echo   Accounting  : http://localhost:3001
echo.
pause
