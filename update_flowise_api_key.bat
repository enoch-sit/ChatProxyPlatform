@echo off
REM Update Flowise API Key and restart flowise-proxy container
REM Usage: double-click or run from ChatProxyPlatform directory

echo.
echo ============================================================
echo    Flowise API Key Update + Container Restart
echo ============================================================
echo.

REM ---------------------------------------------------------------
REM Step 1: Check Python
REM ---------------------------------------------------------------
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo Please install Python 3.8+ from https://www.python.org/downloads/
    pause
    exit /b 1
)

REM ---------------------------------------------------------------
REM Step 2: Check Docker
REM ---------------------------------------------------------------
docker info >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Docker is not running or not installed
    echo Please start Docker Desktop and try again
    pause
    exit /b 1
)

REM ---------------------------------------------------------------
REM Step 3: Ask for the new API key via configure_flowise_api.py
REM ---------------------------------------------------------------
echo [STEP 1/3] Enter your new Flowise API key...
echo.
python configure_flowise_api.py

if errorlevel 1 (
    echo.
    echo [ERROR] API key configuration failed or was cancelled
    echo No changes were made to the container
    pause
    exit /b 1
)

REM ---------------------------------------------------------------
REM Step 4: Restart flowise-proxy with --force-recreate
REM ---------------------------------------------------------------
echo.
echo [STEP 2/3] Restarting flowise-proxy container...
echo.

cd flowise-proxy-service-py
docker compose up -d --force-recreate flowise-proxy

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to restart flowise-proxy
    echo Try manually: cd flowise-proxy-service-py ^&^& docker compose up -d --force-recreate
    cd ..
    pause
    exit /b 1
)

cd ..

REM ---------------------------------------------------------------
REM Step 5: Verify the new key is live inside the container
REM ---------------------------------------------------------------
echo.
echo [STEP 3/3] Verifying new key inside container...
echo.

REM Give container a moment to start
timeout /t 5 /nobreak >nul

for /f %%K in ('docker exec flowise-proxy printenv FLOWISE_API_KEY 2^>nul') do set LIVE_KEY=%%K

if defined LIVE_KEY (
    REM Show only first 8 chars for confirmation, mask the rest
    set PREVIEW=%LIVE_KEY:~0,8%
    echo [OK] FLOWISE_API_KEY is set in container: %PREVIEW%...
) else (
    echo [WARN] Could not read FLOWISE_API_KEY from container
    echo        Container may still be starting - check with:
    echo        docker exec flowise-proxy printenv FLOWISE_API_KEY
)

echo.
echo ============================================================
echo    Done! flowise-proxy is running with the new API key
echo ============================================================
echo.
echo To check logs:  docker logs flowise-proxy --tail=50
echo.
pause
