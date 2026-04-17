@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
title ChatProxy Platform - Drive Configuration Assistant

:: Colors for output (ANSI escape codes)
set "GREEN=[32m"
set "YELLOW=[33m"
set "RED=[31m"
set "BLUE=[36m"
set "RESET=[0m"

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║   ChatProxy Platform - Drive Configuration Assistant          ║
echo ║   Checking system drives and recommending optimal setup       ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

:: Variables
set "HAS_C=0"
set "HAS_D=0"
set "D_IS_RAID=0"
set "C_FREE_GB=0"
set "D_FREE_GB=0"
set "RECOMMEND_D=0"

:: ========================================
:: STEP 1: Detect Available Drives
:: ========================================
echo %BLUE%[STEP 1/5] Detecting available drives...%RESET%
echo.

if exist C:\ (
    set "HAS_C=1"
    echo %GREEN%[✓]%RESET% C: drive detected
) else (
    echo %RED%[✗]%RESET% C: drive NOT found
)

if exist D:\ (
    set "HAS_D=1"
    echo %GREEN%[✓]%RESET% D: drive detected
) else (
    echo %YELLOW%[!]%RESET% D: drive NOT found
)

:: Check for other drives
set "OTHER_DRIVES="
for %%d in (E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist %%d:\ (
        set "OTHER_DRIVES=!OTHER_DRIVES! %%d:"
    )
)

if defined OTHER_DRIVES (
    echo %BLUE%[i]%RESET% Other drives detected:%OTHER_DRIVES%
)

echo.

:: ========================================
:: STEP 2: Check Drive Space
:: ========================================
echo %BLUE%[STEP 2/5] Checking available space...%RESET%
echo.

:: Get C: drive space
for /f "tokens=3" %%a in ('dir C:\ ^| findstr "bytes free"') do (
    set "C_FREE_BYTES=%%a"
)
if defined C_FREE_BYTES (
    set /a "C_FREE_GB=!C_FREE_BYTES:~0,-9!"
    if !C_FREE_GB! GTR 0 (
        echo %GREEN%[✓]%RESET% C: drive free space: ~!C_FREE_GB! GB
    ) else (
        echo %YELLOW%[!]%RESET% C: drive free space: Less than 1 GB
    )
)

:: Get D: drive space if exists
if !HAS_D! EQU 1 (
    for /f "tokens=3" %%a in ('dir D:\ ^| findstr "bytes free"') do (
        set "D_FREE_BYTES=%%a"
    )
    if defined D_FREE_BYTES (
        set /a "D_FREE_GB=!D_FREE_BYTES:~0,-9!"
        if !D_FREE_GB! GTR 0 (
            echo %GREEN%[✓]%RESET% D: drive free space: ~!D_FREE_GB! GB
        ) else (
            echo %YELLOW%[!]%RESET% D: drive free space: Less than 1 GB
        )
    )
)

echo.

:: ========================================
:: STEP 3: Check RAID Configuration
:: ========================================
echo %BLUE%[STEP 3/5] Checking RAID configuration...%RESET%
echo.

:: Check if D: is on RAID array
if !HAS_D! EQU 1 (
    echo Analyzing D: drive configuration...
    
    :: Try to detect RAID using wmic
    wmic diskdrive get Caption,DeviceID,Model,Size,Status >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        :: Check for RAID keywords in disk model
        for /f "tokens=*" %%a in ('wmic diskdrive where "DeviceID like '%%PHYSICALDRIVE%%'" get Model 2^>nul ^| findstr /i "RAID"') do (
            set "D_IS_RAID=1"
            echo %GREEN%[✓]%RESET% RAID array detected: %%a
        )
        
        :: Check for hardware RAID controllers
        for /f "tokens=*" %%a in ('wmic diskdrive get Model 2^>nul ^| findstr /i "PERC LSI Adaptec MegaRAID HP Smart Array"') do (
            set "D_IS_RAID=1"
            echo %GREEN%[✓]%RESET% Hardware RAID controller detected: %%a
        )
        
        :: Check Windows Storage Spaces (Software RAID)
        powershell -Command "Get-StoragePool -IsPrimordial $false -ErrorAction SilentlyContinue" >nul 2>&1
        if !ERRORLEVEL! EQU 0 (
            for /f %%a in ('powershell -Command "Get-StoragePool -IsPrimordial $false -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count"') do (
                if %%a GTR 0 (
                    set "D_IS_RAID=1"
                    echo %GREEN%[✓]%RESET% Windows Storage Spaces detected
                )
            )
        )
    )
    
    if !D_IS_RAID! EQU 1 (
        echo.
        echo %GREEN%[✓] D: drive appears to be on a RAID array%RESET%
        echo %BLUE%    This is EXCELLENT for database storage!%RESET%
        set "RECOMMEND_D=1"
    ) else (
        echo %YELLOW%[i]%RESET% Could not confirm RAID on D: drive
        echo %YELLOW%    (This doesn't mean it's not RAID - detection may require admin rights)%RESET%
        
        :: Still recommend D if it has significantly more space
        if !D_FREE_GB! GTR 50 (
            set "RECOMMEND_D=1"
            echo %BLUE%[i]%RESET% D: has good capacity for data storage
        )
    )
) else (
    echo %YELLOW%[!]%RESET% No D: drive detected - will use C: drive
)

echo.

:: ========================================
:: STEP 4: Provide Recommendations
:: ========================================
echo %BLUE%[STEP 4/5] Configuration Recommendations%RESET%
echo.
echo ════════════════════════════════════════════════════════════════
echo.

if !RECOMMEND_D! EQU 1 (
    echo %GREEN%✓ RECOMMENDED CONFIGURATION:%RESET%
    echo.
    echo   %BLUE%C: Drive (System)%RESET%
    echo   • Windows OS and Docker Desktop
    echo   • Application code (~5 GB)
    echo   • Available space: !C_FREE_GB! GB
    echo.
    echo   %GREEN%D: Drive (Data - RECOMMENDED)%RESET%
    echo   • Docker volumes (databases)
    echo   • MongoDB and PostgreSQL data
    echo   • User uploads and file storage
    echo   • Logs and backups
    echo   • Available space: !D_FREE_GB! GB
    echo.
    if !D_IS_RAID! EQU 1 (
        echo   %GREEN%[RAID Detected]%RESET% Data protection and performance benefits!
    )
    echo.
    echo   %BLUE%Benefits:%RESET%
    echo   • Better performance (separate I/O from system drive)
    if !D_IS_RAID! EQU 1 (
        echo   • Data redundancy (RAID protection)
    )
    echo   • More capacity for data growth
    echo   • Easier backup management
    echo.
) else (
    echo %YELLOW%! BASIC CONFIGURATION:%RESET%
    echo.
    echo   %BLUE%C: Drive (All-in-One)%RESET%
    echo   • Windows OS and Docker Desktop
    echo   • Application code
    echo   • All Docker volumes and data
    echo   • Available space: !C_FREE_GB! GB
    echo.
    if !C_FREE_GB! LSS 50 (
        echo   %RED%[WARNING]%RESET% Limited space on C: drive
        echo   Consider adding more storage for production use
        echo.
    )
)

echo ════════════════════════════════════════════════════════════════
echo.

:: ========================================
:: STEP 5: Setup Assistant
:: ========================================
echo %BLUE%[STEP 5/5] Setup Options%RESET%
echo.

if !RECOMMEND_D! EQU 1 (
    echo Would you like to:
    echo   [1] Create optimal directory structure on D: drive
    echo   [2] Generate docker-compose configuration for D: drive
    echo   [3] View detailed setup instructions
    echo   [4] Skip - I'll configure manually
    echo.
    set /p "CHOICE=Enter your choice (1-4): "
    
    if "!CHOICE!"=="1" goto CREATE_DIRS
    if "!CHOICE!"=="2" goto GENERATE_CONFIG
    if "!CHOICE!"=="3" goto SHOW_INSTRUCTIONS
    if "!CHOICE!"=="4" goto END_SCRIPT
    
    echo %RED%Invalid choice%RESET%
    goto END_SCRIPT
) else (
    echo Would you like to:
    echo   [1] Create directory structure on C: drive
    echo   [2] View setup instructions for single drive
    echo   [3] Skip - I'll configure manually
    echo.
    set /p "CHOICE=Enter your choice (1-3): "
    
    if "!CHOICE!"=="1" goto CREATE_DIRS_C
    if "!CHOICE!"=="2" goto SHOW_INSTRUCTIONS_C
    if "!CHOICE!"=="3" goto END_SCRIPT
    
    echo %RED%Invalid choice%RESET%
    goto END_SCRIPT
)

:: ========================================
:: CREATE DIRECTORIES ON D: DRIVE
:: ========================================
:CREATE_DIRS
echo.
echo %BLUE%Creating directory structure on D: drive...%RESET%
echo.

set "DATA_ROOT=D:\ChatProxyData"
set "VOLUMES_ROOT=D:\DockerVolumes"

:: Create main directories
echo Creating %DATA_ROOT%...
mkdir "%DATA_ROOT%" 2>nul
mkdir "%DATA_ROOT%\uploads" 2>nul
mkdir "%DATA_ROOT%\logs" 2>nul
mkdir "%DATA_ROOT%\backups" 2>nul

echo Creating %VOLUMES_ROOT%...
mkdir "%VOLUMES_ROOT%" 2>nul
mkdir "%VOLUMES_ROOT%\mongodb-auth" 2>nul
mkdir "%VOLUMES_ROOT%\mongodb-proxy" 2>nul
mkdir "%VOLUMES_ROOT%\postgres-accounting" 2>nul
mkdir "%VOLUMES_ROOT%\flowise-postgres" 2>nul

echo.
echo %GREEN%✓ Directory structure created successfully!%RESET%
echo.
echo Created directories:
echo   %VOLUMES_ROOT%\mongodb-auth
echo   %VOLUMES_ROOT%\mongodb-proxy
echo   %VOLUMES_ROOT%\postgres-accounting
echo   %VOLUMES_ROOT%\flowise-postgres
echo   %DATA_ROOT%\uploads
echo   %DATA_ROOT%\logs
echo   %DATA_ROOT%\backups
echo.

:: Create a configuration note file
echo # ChatProxy Platform - D: Drive Configuration > "%DATA_ROOT%\README.txt"
echo. >> "%DATA_ROOT%\README.txt"
echo This directory contains ChatProxy Platform data files. >> "%DATA_ROOT%\README.txt"
echo. >> "%DATA_ROOT%\README.txt"
echo Created: %date% %time% >> "%DATA_ROOT%\README.txt"
echo. >> "%DATA_ROOT%\README.txt"
echo Directory Structure: >> "%DATA_ROOT%\README.txt"
echo - uploads/  : User uploaded files >> "%DATA_ROOT%\README.txt"
echo - logs/     : Service logs >> "%DATA_ROOT%\README.txt"
echo - backups/  : Database backups >> "%DATA_ROOT%\README.txt"
echo. >> "%DATA_ROOT%\README.txt"
echo Docker Volumes: >> "%DATA_ROOT%\README.txt"
echo - D:\DockerVolumes\mongodb-auth >> "%DATA_ROOT%\README.txt"
echo - D:\DockerVolumes\mongodb-proxy >> "%DATA_ROOT%\README.txt"
echo - D:\DockerVolumes\postgres-accounting >> "%DATA_ROOT%\README.txt"
echo - D:\DockerVolumes\flowise-postgres >> "%DATA_ROOT%\README.txt"

echo %GREEN%✓ Configuration documentation saved to: %DATA_ROOT%\README.txt%RESET%
echo.

pause
goto GENERATE_CONFIG

:: ========================================
:: CREATE DIRECTORIES ON C: DRIVE
:: ========================================
:CREATE_DIRS_C
echo.
echo %BLUE%Creating directory structure on C: drive...%RESET%
echo.

set "DATA_ROOT=C:\ChatProxyData"
set "VOLUMES_ROOT=C:\DockerVolumes"

mkdir "%DATA_ROOT%" 2>nul
mkdir "%DATA_ROOT%\uploads" 2>nul
mkdir "%DATA_ROOT%\logs" 2>nul
mkdir "%DATA_ROOT%\backups" 2>nul

echo.
echo %GREEN%✓ Directory structure created!%RESET%
echo.

pause
goto SHOW_INSTRUCTIONS_C

:: ========================================
:: GENERATE DOCKER-COMPOSE CONFIGURATION
:: ========================================
:GENERATE_CONFIG
echo.
echo %BLUE%Generating docker-compose configuration suggestions...%RESET%
echo.

set "CONFIG_FILE=docker-volumes-d-drive.txt"

echo # Docker Compose Volume Configuration for D: Drive > "%CONFIG_FILE%"
echo # Generated: %date% %time% >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo ================================================================ >> "%CONFIG_FILE%"
echo UPDATE THESE FILES TO USE D: DRIVE FOR DATA: >> "%CONFIG_FILE%"
echo ================================================================ >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo 1. auth-service/docker-compose.dev.yml >> "%CONFIG_FILE%"
echo ---------------------------------------- >> "%CONFIG_FILE%"
echo   mongodb-auth: >> "%CONFIG_FILE%"
echo     volumes: >> "%CONFIG_FILE%"
echo       - D:/DockerVolumes/mongodb-auth:/data/db >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo 2. accounting-service/docker-compose.yml >> "%CONFIG_FILE%"
echo ---------------------------------------- >> "%CONFIG_FILE%"
echo   postgres-accounting: >> "%CONFIG_FILE%"
echo     volumes: >> "%CONFIG_FILE%"
echo       - D:/DockerVolumes/postgres-accounting:/var/lib/postgresql/data >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo 3. flowise/docker-compose.yml >> "%CONFIG_FILE%"
echo ---------------------------------------- >> "%CONFIG_FILE%"
echo   flowise-postgres: >> "%CONFIG_FILE%"
echo     volumes: >> "%CONFIG_FILE%"
echo       - D:/DockerVolumes/flowise-postgres:/var/lib/postgresql/data >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo 4. flowise-proxy-service-py/docker-compose.yml >> "%CONFIG_FILE%"
echo ---------------------------------------- >> "%CONFIG_FILE%"
echo   mongodb: >> "%CONFIG_FILE%"
echo     volumes: >> "%CONFIG_FILE%"
echo       - D:/DockerVolumes/mongodb-proxy:/data/db >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo ================================================================ >> "%CONFIG_FILE%"
echo ENVIRONMENT VARIABLE UPDATES: >> "%CONFIG_FILE%"
echo ================================================================ >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo flowise-proxy-service-py/.env: >> "%CONFIG_FILE%"
echo   FILE_STORAGE_PATH=D:/ChatProxyData/uploads >> "%CONFIG_FILE%"
echo   LOG_PATH=D:/ChatProxyData/logs >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo ================================================================ >> "%CONFIG_FILE%"
echo BACKUP SCRIPT LOCATION: >> "%CONFIG_FILE%"
echo ================================================================ >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"
echo Update backup scripts to use: D:\ChatProxyData\backups >> "%CONFIG_FILE%"
echo. >> "%CONFIG_FILE%"

echo %GREEN%✓ Configuration saved to: %CONFIG_FILE%%RESET%
echo.
echo This file contains the exact changes needed for each docker-compose.yml file.
echo.

start notepad "%CONFIG_FILE%"

pause
goto SHOW_INSTRUCTIONS

:: ========================================
:: SHOW DETAILED INSTRUCTIONS (D: DRIVE)
:: ========================================
:SHOW_INSTRUCTIONS
cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║   D: Drive Configuration - Step-by-Step Instructions          ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo %GREEN%STEP 1: Stop all running services%RESET%
echo   cd flowise ^&^& stop.bat
echo   cd ..\auth-service ^&^& stop.bat
echo   cd ..\accounting-service ^&^& stop.bat
echo   cd ..\flowise-proxy-service-py ^&^& stop.bat
echo   cd ..\bridge ^&^& stop.bat
echo.
echo %GREEN%STEP 2: Update docker-compose.yml files%RESET%
echo   Edit each service's docker-compose.yml to use D: drive volumes
echo   (See generated file: docker-volumes-d-drive.txt)
echo.
echo %GREEN%STEP 3: Update environment variables%RESET%
echo   flowise-proxy-service-py/.env:
echo     FILE_STORAGE_PATH=D:/ChatProxyData/uploads
echo     LOG_PATH=D:/ChatProxyData/logs
echo.
echo %GREEN%STEP 4: Restart all services%RESET%
echo   cd flowise ^&^& start-with-postgres.bat
echo   cd ..\auth-service ^&^& start.bat
echo   cd ..\accounting-service ^&^& start.bat
echo   cd ..\flowise-proxy-service-py ^&^& docker-compose up -d
echo   cd ..\bridge ^&^& start.bat
echo.
echo %GREEN%STEP 5: Verify%RESET%
echo   Run: check_system.bat
echo   Check that all services are running
echo.
echo %BLUE%TIP:%RESET% If migrating existing data, copy volumes before restarting:
echo   xcopy /E /I "C:\ProgramData\Docker\volumes\*" "D:\DockerVolumes\"
echo.
echo ════════════════════════════════════════════════════════════════
pause
goto END_SCRIPT

:: ========================================
:: SHOW INSTRUCTIONS (C: DRIVE ONLY)
:: ========================================
:SHOW_INSTRUCTIONS_C
cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║   Single Drive Configuration - Setup Instructions             ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo %YELLOW%Your system will use C: drive for all data.%RESET%
echo.
echo %GREEN%Current configuration is already optimized for C: drive.%RESET%
echo.
echo Just follow the standard deployment process:
echo.
echo 1. Run: check_system.bat
echo 2. Follow: DEPLOYMENT_PLAN.md
echo 3. Start services as documented
echo.
echo %BLUE%IMPORTANT:%RESET% Ensure you have at least 50 GB free on C: drive
echo Current C: drive space: !C_FREE_GB! GB
echo.
if !C_FREE_GB! LSS 50 (
    echo %RED%[WARNING]%RESET% Low disk space detected!
    echo   Consider freeing up space or adding external storage
    echo.
)
echo ════════════════════════════════════════════════════════════════
pause
goto END_SCRIPT

:: ========================================
:: END SCRIPT
:: ========================================
:END_SCRIPT
echo.
echo %GREEN%Drive configuration check complete!%RESET%
echo.
echo Next steps:
echo   1. Review the recommendations above
echo   2. Configure docker-compose files if using D: drive
echo   3. Run check_system.bat to verify system readiness
echo   4. Follow DEPLOYMENT_PLAN.md for full setup
echo.
echo For more information, see:
echo   • README.md - Complete documentation
echo   • DEPLOYMENT_PLAN.md - Installation guide
echo   • docs/SERVICE_ARCHITECTURE.md - Architecture details
echo.

pause
endlocal
