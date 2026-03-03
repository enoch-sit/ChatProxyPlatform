@echo off
REM ============================================================================
REM ChatProxyPlatform - Automated Setup with Prerequisites Check
REM ============================================================================
REM
REM This script:
REM 1. Checks for Docker, Node.js, Python, Git
REM 2. Installs missing prerequisites automatically
REM 3. Handles Docker Desktop + WSL2 installation and reboot
REM 4. Runs the Python setup script
REM
REM Usage: automated_setup.bat
REM ============================================================================

setlocal enabledelayedexpansion

REM Ensure we are in the script directory
cd /d "%~dp0"

echo.
echo ================================================================================
echo ChatProxyPlatform - Automated Setup
echo ================================================================================
echo Machine: %COMPUTERNAME%
echo User:    %USERNAME%
echo Date:    %DATE% %TIME%
echo Dir:     %CD%
echo ================================================================================
echo.

REM ============================================================================
REM Step 1: Check Prerequisites
REM ============================================================================
echo [Step 1/2] Checking prerequisites...
echo.

set NEED_INSTALL=0
set NEED_REBOOT=0
set MISSING_LIST=
set CHECK_PYTHON=MISSING
set CHECK_NODE=MISSING
set CHECK_NPM=MISSING
set CHECK_DOCKER=MISSING
set CHECK_DOCKER_DAEMON=MISSING
set CHECK_GIT=MISSING

REM -------------------------------------------------------
REM Check Python
REM -------------------------------------------------------
echo Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo   [MISSING] Python is NOT installed
    set NEED_INSTALL=1
    set MISSING_LIST=!MISSING_LIST! Python
    set CHECK_PYTHON=MISSING
) else (
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do (
        echo   [OK] %%i
        set CHECK_PYTHON=OK
    )
)

REM -------------------------------------------------------
REM Check Node.js
REM -------------------------------------------------------
echo Checking Node.js...
node --version >nul 2>&1
if errorlevel 1 (
    echo   [MISSING] Node.js is NOT installed
    set NEED_INSTALL=1
    set MISSING_LIST=!MISSING_LIST! Node.js
    set CHECK_NODE=MISSING
) else (
    for /f "tokens=*" %%i in ('node --version 2^>^&1') do (
        echo   [OK] Node.js %%i
        set CHECK_NODE=OK
    )
)

REM -------------------------------------------------------
REM Check npm (may be npm or npm.cmd depending on system)
REM -------------------------------------------------------
echo Checking npm...
where npm >nul 2>&1
if errorlevel 1 (
    where npm.cmd >nul 2>&1
    if errorlevel 1 (
        echo   [MISSING] npm is NOT found in PATH
        set CHECK_NPM=MISSING
    ) else (
        echo   [OK] npm.cmd found
        set CHECK_NPM=OK
    )
) else (
    npm --version >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] npm found but version check failed
        set CHECK_NPM=WARN
    ) else (
        for /f "tokens=*" %%i in ('npm --version 2^>^&1') do (
            echo   [OK] npm %%i
            set CHECK_NPM=OK
        )
    )
)

REM -------------------------------------------------------
REM Check Docker (installation)
REM -------------------------------------------------------
echo Checking Docker...
where docker >nul 2>&1
if errorlevel 1 (
    echo   [MISSING] Docker is NOT installed (not found in PATH)
    set NEED_INSTALL=1
    set NEED_REBOOT=1
    set MISSING_LIST=!MISSING_LIST! Docker
    set CHECK_DOCKER=MISSING
    set CHECK_DOCKER_DAEMON=N/A
) else (
    docker --version >nul 2>&1
    if errorlevel 1 (
        echo   [MISSING] Docker command found but not working
        set NEED_INSTALL=1
        set NEED_REBOOT=1
        set MISSING_LIST=!MISSING_LIST! Docker
        set CHECK_DOCKER=BROKEN
        set CHECK_DOCKER_DAEMON=N/A
    ) else (
        for /f "tokens=*" %%i in ('docker --version 2^>^&1') do (
            echo   [OK] %%i
            set CHECK_DOCKER=OK
        )

        REM Check if Docker daemon is running
        echo   Checking Docker daemon...
        docker ps >nul 2>&1
        if errorlevel 1 (
            echo   [STOPPED] Docker Desktop is NOT running
            echo.
            echo   *** ACTION REQUIRED ***
            echo   1. Open Docker Desktop from the Start Menu
            echo   2. Wait for the green icon in the system tray
            echo   3. Then press any key here to continue...
            echo.
            set CHECK_DOCKER_DAEMON=STOPPED
            pause
        ) else (
            echo   [OK] Docker daemon is running
            set CHECK_DOCKER_DAEMON=OK
        )
    )
)

REM -------------------------------------------------------
REM Check Git
REM -------------------------------------------------------
echo Checking Git...
where git >nul 2>&1
if errorlevel 1 (
    echo   [OPTIONAL] Git is NOT installed
    set MISSING_LIST=!MISSING_LIST! Git(optional)
    set CHECK_GIT=MISSING
) else (
    git --version >nul 2>&1
    if errorlevel 1 (
        echo   [WARN] Git found but version check failed
        set CHECK_GIT=WARN
    ) else (
        for /f "tokens=*" %%i in ('git --version 2^>^&1') do (
            echo   [OK] %%i
            set CHECK_GIT=OK
        )
    )
)

echo.

REM -------------------------------------------------------
REM Print Summary of all checks
REM -------------------------------------------------------
echo ================================================================================
echo Prerequisites Summary:
echo ================================================================================
echo   Python:         %CHECK_PYTHON%
echo   Node.js:        %CHECK_NODE%
echo   npm:            %CHECK_NPM%
echo   Docker:         %CHECK_DOCKER%
echo   Docker Daemon:  %CHECK_DOCKER_DAEMON%
echo   Git:            %CHECK_GIT%
echo ================================================================================
echo.

REM Abort if Docker daemon is stopped (user must start Docker Desktop)
if "%CHECK_DOCKER_DAEMON%"=="STOPPED" (
    echo [ERROR] Docker Desktop must be running before setup can continue.
    echo.
    echo Please:
    echo   1. Start Docker Desktop from the Start Menu
    echo   2. Wait for it to fully load (green icon in the system tray)
    echo   3. Run this script again: automated_setup.bat
    echo.
    pause
    exit /b 1
)

echo.

REM ============================================================================
REM Step 2: Install Missing Prerequisites
REM ============================================================================
if %NEED_INSTALL%==1 (
    echo ================================================================================
    echo [Step 2/2] Installing Missing Prerequisites
    echo ================================================================================
    echo.
    echo Missing software:%MISSING_LIST%
    echo.
    
    REM Check if winget is available
    echo Checking if winget package manager is available...
    where winget >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] winget is not available on this system
        echo.
        echo Please manually install the missing software:
        echo   - Python 3.12:      https://www.python.org/downloads/
        echo   - Node.js LTS:      https://nodejs.org/
        echo   - Docker Desktop:   https://www.docker.com/products/docker-desktop/
        echo   - Git:              https://git-scm.com/downloads/
        echo.
        echo After installing, run this script again: automated_setup.bat
        echo.
        pause
        exit /b 1
    )
    echo   [OK] winget is available
    echo.
    
    echo Installing prerequisites using winget...
    echo This may take 5-10 minutes. Please wait...
    echo.
    
    REM Install Python if missing
    if "%CHECK_PYTHON%"=="MISSING" (
        echo [Installing] Python 3.12...
        winget install -e --id Python.Python.3.12 --accept-source-agreements --accept-package-agreements --silent
        if errorlevel 1 (
            echo   [WARN] Python install may have failed - check above output
        ) else (
            echo   [OK] Python installed
        )
    )
    
    REM Install Node.js if missing
    if "%CHECK_NODE%"=="MISSING" (
        echo [Installing] Node.js LTS...
        winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
        if errorlevel 1 (
            echo   [WARN] Node.js install may have failed - check above output
        ) else (
            echo   [OK] Node.js installed
        )
    )
    
    REM Install Docker if missing
    if "%CHECK_DOCKER%"=="MISSING" (
        echo [Installing] Docker Desktop...
        echo NOTE: Docker requires WSL2 and a system reboot after installation
        winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
        if errorlevel 1 (
            echo   [WARN] Docker install may have failed - check above output
        ) else (
            echo   [OK] Docker Desktop installed
        )
    )
    
    REM Install Git if missing (optional)
    if "%CHECK_GIT%"=="MISSING" (
        echo [Installing] Git (optional)...
        winget install -e --id Git.Git --accept-source-agreements --accept-package-agreements --silent
        if errorlevel 1 (
            echo   [WARN] Git install may have failed (optional - can continue without it)
        ) else (
            echo   [OK] Git installed
        )
    )
    
    echo.
    echo ================================================================================
    echo Installation Complete
    echo ================================================================================
    echo.
    
    if %NEED_REBOOT%==1 (
        echo ================================================================================
        echo [IMPORTANT] System Restart Required
        echo ================================================================================
        echo.
        echo Docker Desktop was installed and requires WSL2 to be enabled.
        echo.
        echo Next steps:
        echo   1. RESTART YOUR COMPUTER
        echo   2. After restart, open Docker Desktop from the Start Menu
        echo   3. Wait for the green icon in the system tray
        echo   4. Run this script again: automated_setup.bat
        echo.
        echo ================================================================================
        echo.
        pause
        exit /b 0
    ) else (
        echo ================================================================================
        echo [IMPORTANT] Close and reopen this terminal for PATH changes to take effect
        echo Then run this script again: automated_setup.bat
        echo ================================================================================
        echo.
        pause
        exit /b 0
    )
)

REM ============================================================================
REM Step 2/2: Run Python Setup Script
REM ============================================================================
echo [Step 2/2] Running automated setup...
echo.

REM Check if automated_setup.py exists
if not exist "%~dp0automated_setup.py" (
    echo [ERROR] automated_setup.py not found in: %~dp0
    echo.
    echo Please make sure you are running this from the ChatProxyPlatform root directory.
    echo.
    pause
    exit /b 1
)

REM Final Docker daemon check before launching Python
echo Verifying Docker is ready...
docker ps >nul 2>&1
if errorlevel 1 (
    echo.
    echo [ERROR] Docker Desktop is not running!
    echo.
    echo Please:
    echo   1. Open Docker Desktop from the Start Menu
    echo   2. Wait for it to fully start (green icon in the system tray)
    echo   3. Run this script again: automated_setup.bat
    echo.
    pause
    exit /b 1
)
echo   [OK] Docker is ready
echo.

REM Run the Python setup script
echo Starting ChatProxyPlatform setup...
echo ================================================================================
echo.
python "%~dp0automated_setup.py"

REM Capture exit code
set EXIT_CODE=%errorlevel%

echo.
if %EXIT_CODE% equ 0 (
    echo ================================================================================
    echo Setup completed successfully!
    echo ================================================================================
    echo.
    echo Access your services:
    echo   - Bridge UI: http://localhost:8080
    echo   - Flowise: http://localhost:3002
    echo   - MailHog: http://localhost:8025
    echo.
    echo Default admin credentials:
    echo   - Email: admin@example.com
    echo   - Password: Admin123!
    echo.
) else (
    echo ================================================================================
    echo Setup encountered errors. Please review the output above.
    echo ================================================================================
)

echo.
echo Press any key to exit...
pause >nul

exit /b %EXIT_CODE%
