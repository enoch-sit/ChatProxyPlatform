@echo off
REM ============================================================================
REM ChatProxyPlatform - Quick Install for Multiple Computers
REM ============================================================================
REM
REM This script installs prerequisites and runs automated setup
REM Designed for rapid deployment on multiple machines
REM
REM Usage: quick_install.bat
REM ============================================================================

setlocal enabledelayedexpansion

echo.
echo ================================================================================
echo ChatProxyPlatform - Quick Installation for Multiple Computers
echo ================================================================================
echo.
echo This will install:
echo   - Docker Desktop
echo   - Node.js LTS
echo   - Python 3.12
echo   - Git
echo.
echo And then run automated setup.
echo.
pause

echo.
echo ================================================================================
echo Step 1: Installing Prerequisites
echo ================================================================================
echo.

REM Check if winget is available
winget --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] winget is not available on this system
    echo.
    echo Please manually install:
    echo   1. Docker Desktop: https://www.docker.com/products/docker-desktop/
    echo   2. Node.js LTS: https://nodejs.org/
    echo   3. Python 3.12+: https://www.python.org/downloads/
    echo   4. Git: https://git-scm.com/downloads/
    echo.
    echo Then run: automated_setup.bat
    echo.
    pause
    exit /b 1
)

echo Installing Docker Desktop...
winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
if errorlevel 1 (
    echo [WARNING] Docker Desktop installation may have failed or is already installed
)

echo.
echo Installing Node.js LTS...
winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
if errorlevel 1 (
    echo [WARNING] Node.js installation may have failed or is already installed
)

echo.
echo Installing Python 3.12...
winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements
if errorlevel 1 (
    echo [WARNING] Python installation may have failed or is already installed
)

echo.
echo Installing Git...
winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements
if errorlevel 1 (
    echo [WARNING] Git installation may have failed or is already installed
)

echo.
echo ================================================================================
echo Step 2: Restart Required
echo ================================================================================
echo.
echo IMPORTANT: Some installations may require a system restart or terminal restart
echo to update PATH variables.
echo.
echo Before continuing:
echo   1. RESTART this terminal (close and reopen)
echo   2. OR restart your computer if Docker was just installed
echo   3. START Docker Desktop and wait for it to be ready
echo.
echo After restarting and starting Docker Desktop:
echo   - Run: automated_setup.bat
echo.
echo ================================================================================
echo.
echo Do you want to continue with automated setup now? (y/n)
echo (Only select 'y' if you've already restarted the terminal)
echo.
set /p CONTINUE="Continue? (y/n): "

if /i "%CONTINUE%" NEQ "y" (
    echo.
    echo Setup paused. Please:
    echo   1. Restart this terminal
    echo   2. Start Docker Desktop
    echo   3. Run: automated_setup.bat
    echo.
    pause
    exit /b 0
)

echo.
echo ================================================================================
echo Step 3: Starting Docker Desktop
echo ================================================================================
echo.
echo Please make sure Docker Desktop is running...
echo.
echo Checking Docker status...
timeout /t 5 /nobreak >nul

docker --version >nul 2>&1
if errorlevel 1 (
    echo [WARNING] Docker is not detected yet.
    echo.
    echo Please:
    echo   1. Open Docker Desktop manually
    echo   2. Wait for it to fully start
    echo   3. Then press any key to continue...
    pause >nul
)

echo.
echo ================================================================================
echo Step 4: Running Automated Setup
echo ================================================================================
echo.

REM Change to script directory
cd /d "%~dp0"

REM Run automated setup
call automated_setup.bat

echo.
echo ================================================================================
echo Installation Complete!
echo ================================================================================
echo.
echo If you encountered any errors, please check:
echo   - Docker Desktop is running
echo   - All prerequisites are properly installed
echo   - You have sufficient disk space
echo.
echo For detailed troubleshooting, see: DEPLOYMENT_CHECKLIST.md
echo.
pause
exit /b %errorlevel%
