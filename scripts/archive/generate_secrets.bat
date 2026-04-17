@echo off
REM ============================================================================
REM ChatProxy Platform - JWT Secret Generator Launcher
REM Runs the Python script to generate and populate JWT secrets
REM Author: Enoch Sit
REM License: MIT
REM ============================================================================

setlocal enabledelayedexpansion

REM Change to script directory
cd /d "%~dp0"

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║   ChatProxy Platform - JWT Secret Generator                   ║
echo ║   Generating and populating JWT secrets...                    ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

REM Check if Python is installed
where python >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Python not found in PATH
    echo [INFO] Please install Python 3.8+ from https://www.python.org/
    echo [INFO] Make sure to check "Add Python to PATH" during installation
    pause
    exit /b 1
)

REM Get Python version
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
echo [INFO] Python version: %PYTHON_VERSION%

REM Run the Python script
echo [INFO] Running generate_secrets.py...
echo.

python generate_secrets.py

set EXIT_CODE=%errorlevel%

echo.
if %EXIT_CODE% equ 0 (
    echo ════════════════════════════════════════════════════════════════
    echo [SUCCESS] JWT secrets generated and populated successfully!
    echo ════════════════════════════════════════════════════════════════
    echo.
    echo Next steps:
    echo   1. Review .env files to confirm secrets are populated
    echo   2. Start services: docker compose up -d
    echo   3. Check logs: docker compose logs -f
    echo.
) else (
    echo ════════════════════════════════════════════════════════════════
    echo [ERROR] Script failed with exit code %EXIT_CODE%
    echo ════════════════════════════════════════════════════════════════
    echo.
    echo Troubleshooting:
    echo   - Ensure .env files exist (run setup_env_files.bat first)
    echo   - Check file permissions
    echo   - Review error messages above
    echo.
)

pause
exit /b %EXIT_CODE%
