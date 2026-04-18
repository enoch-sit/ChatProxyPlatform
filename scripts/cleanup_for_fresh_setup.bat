@echo off
REM ============================================================================
REM ChatProxyPlatform - Cleanup Script
REM ============================================================================
REM
REM This script removes all Docker containers, volumes, and cleans up the
REM installation so you can test the automated setup from scratch.
REM
REM WARNING: This will delete all data including databases!
REM
REM Usage: cleanup_for_fresh_setup.bat
REM ============================================================================

setlocal enabledelayedexpansion

echo.
echo ================================================================================
echo ChatProxyPlatform - Cleanup for Fresh Setup Test
echo ================================================================================
echo.
echo WARNING: This will delete ALL Docker containers, volumes, and data!
echo.
echo This includes:
echo   - All running containers
echo   - All Docker volumes (MongoDB, PostgreSQL data)
echo   - User accounts and credit allocations
echo   - Chat histories and sessions
echo.
echo You will need to run automated_setup.bat after this to reinstall.
echo.

set /p CONFIRM="Are you sure you want to continue? (yes/no): "
if /i not "%CONFIRM%"=="yes" (
    echo.
    echo Cleanup cancelled.
    pause
    exit /b 0
)

echo.
echo Starting cleanup...
echo.

REM Stop all services
echo [1/6] Stopping all services...

cd "%~dp0flowise" 2>nul
if exist "stop.bat" call stop.bat >nul 2>&1

cd "%~dp0auth-service" 2>nul
if exist "stop.bat" call stop.bat >nul 2>&1

cd "%~dp0accounting-service" 2>nul
if exist "stop.bat" call stop.bat >nul 2>&1

cd "%~dp0flowise-proxy-service-py" 2>nul
if exist "stop.bat" call stop.bat >nul 2>&1

cd "%~dp0bridge" 2>nul
if exist "stop.bat" call stop.bat >nul 2>&1

cd "%~dp0"

echo   Services stopped.
timeout /t 2 >nul

REM Stop all containers forcefully
echo [2/6] Stopping all Docker containers...
docker stop flowise flowise-postgres auth-service mongodb-auth auth-mailhog accounting-service postgres-accounting flowise-proxy mongodb-proxy bridge-ui >nul 2>&1
echo   All containers stopped.

REM Remove all containers
echo [3/6] Removing all Docker containers...
docker rm -f flowise flowise-postgres auth-service mongodb-auth auth-mailhog accounting-service postgres-accounting flowise-proxy mongodb-proxy bridge-ui >nul 2>&1
echo   All containers removed.

REM Remove all volumes (DATA WILL BE LOST!)
echo [4/8] Removing all Docker volumes...
docker volume rm flowise-data flowise-postgres mongodb-auth mongodb-proxy postgres-accounting >nul 2>&1
echo   Named volumes removed.

REM Remove volume directories on all drives
echo [5/9] Removing volume directories from all drives...
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\DockerVolumes" (
        echo   Found DockerVolumes on %%D: drive - removing...
        rmdir /s /q "%%D:\DockerVolumes" 2>nul
        if exist "%%D:\DockerVolumes" (
            echo   WARNING: Could not fully remove %%D:\DockerVolumes - may need admin rights
        ) else (
            echo   %%D:\DockerVolumes removed successfully
        )
    )
)

REM Remove Flowise hidden directory in user home
echo [6/9] Removing Flowise data from user home directory...
if exist "%USERPROFILE%\.flowise" (
    echo   Found .flowise directory in user home - removing...
    rmdir /s /q "%USERPROFILE%\.flowise" 2>nul
    if exist "%USERPROFILE%\.flowise" (
        echo   WARNING: Could not fully remove .flowise directory
    ) else (
        echo   .flowise directory removed successfully
    )
) else (
    echo   No .flowise directory found in user home
)

REM Remove network
echo [7/9] Removing Docker network...
docker network rm chatproxy-network >nul 2>&1
echo   Network removed.

REM Clean up node_modules and build artifacts (optional)
echo [8/9] Cleaning build artifacts (optional)...

if exist "auth-service\node_modules" (
    echo   Removing auth-service\node_modules...
    rmdir /s /q "auth-service\node_modules" 2>nul
)

if exist "accounting-service\node_modules" (
    echo   Removing accounting-service\node_modules...
    rmdir /s /q "accounting-service\node_modules" 2>nul
)

if exist "bridge\node_modules" (
    echo   Removing bridge\node_modules...
    rmdir /s /q "bridge\node_modules" 2>nul
)

echo   Build artifacts cleaned.

REM Prune Docker system (remove unused images, networks, etc.)
echo [9/9] Pruning Docker system (removes unused resources)...
docker system prune -f >nul 2>&1
echo   Docker system pruned.

echo.
echo ================================================================================
echo Cleanup Complete!
echo ================================================================================
echo.
echo Your system is now in a fresh state. All Docker containers, volumes, and
echo data have been removed.
echo.
echo To test the automated setup, run:
echo   automated_setup.bat
echo.
echo This will install everything from scratch and give you admin with 10,000 credits.
echo.
echo ================================================================================
echo.

REM Display current Docker status
echo Current Docker status:
echo.
docker ps -a
echo.

pause
