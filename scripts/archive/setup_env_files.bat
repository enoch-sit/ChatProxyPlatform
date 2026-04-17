@echo off
REM Setup Environment Files for ChatProxy Platform
REM Run this script after git clone to create all necessary .env files

setlocal enabledelayedexpansion

title ChatProxy Platform - Environment Setup

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║   ChatProxy Platform - Environment File Setup                  ║
echo ║   Creating .env files from templates                           ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

set "SCRIPT_DIR=%~dp0"
set "COPIED=0"
set "SKIPPED=0"
set "ERRORS=0"

echo [INFO] Checking for .env.example files...
echo.

REM Function to copy .env.example to .env
call :copy_env_file "flowise" "Flowise AI Flow Builder"
call :copy_env_file "auth-service" "Authentication Service"
call :copy_env_file "accounting-service" "Accounting Service"
call :copy_env_file "flowise-proxy-service-py" "Flowise Proxy Service"
call :copy_env_file "bridge" "Bridge UI Frontend"

echo.
echo ════════════════════════════════════════════════════════════════
echo Summary:
echo   [32m✓[0m Copied: %COPIED%
echo   [33m○[0m Skipped: %SKIPPED%
echo   [31m✗[0m Errors: %ERRORS%
echo ════════════════════════════════════════════════════════════════
echo.

if !COPIED! GTR 0 (
    echo [32m[SUCCESS][0m Environment files created successfully!
    echo.
    echo [33m[IMPORTANT][0m Next steps:
    echo.
    echo 1. Generate and populate JWT secrets automatically:
    echo    generate_secrets.bat
    echo.
    echo 2. Configure drive paths (optional):
    echo    configure_drives.bat
    echo.
    echo 3. Review and customize other settings in each .env file
    echo.
    echo 4. Run system check:
    echo    check_system.bat
    echo.
    echo 5. Follow deployment guide:
    echo    DEPLOYMENT_PLAN.md
    echo.
) else (
    echo [33m[INFO][0m All .env files already exist or no templates found
    echo.
)

pause
goto :eof

REM ============================================
REM Function to copy .env.example to .env
REM ============================================
:copy_env_file
set "service_dir=%~1"
set "service_name=%~2"
set "example_file=%SCRIPT_DIR%%service_dir%\.env.example"
set "target_file=%SCRIPT_DIR%%service_dir%\.env"

if not exist "%example_file%" (
    echo [33m[SKIP][0m %service_name% - No .env.example found
    set /a SKIPPED+=1
    exit /b 0
)

if exist "%target_file%" (
    echo [33m[SKIP][0m %service_name% - .env already exists
    set /a SKIPPED+=1
    exit /b 0
)

copy "%example_file%" "%target_file%" >nul 2>&1
if errorlevel 1 (
    echo [31m[ERROR][0m %service_name% - Failed to copy .env file
    set /a ERRORS+=1
) else (
    echo [32m[OK][0m %service_name% - Created .env file
    set /a COPIED+=1
)

exit /b 0
