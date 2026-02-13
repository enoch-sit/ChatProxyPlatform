@echo off
REM ============================================================================
REM ChatProxyPlatform - Automated Setup Launcher
REM ============================================================================
REM
REM This batch file launches the automated setup Python script.
REM It handles environment checking and provides a clean user experience.
REM
REM Usage: automated_setup.bat
REM ============================================================================

setlocal enabledelayedexpansion

REM Ensure we are in the script directory (fixes Admin run issue)
cd /d "%~dp0"

echo.
echo ================================================================================
echo ChatProxyPlatform - Automated Setup
echo ================================================================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo.
    echo Please install Python 3.8 or higher from: https://www.python.org/downloads/
    echo Make sure to check "Add Python to PATH" during installation
    echo.
    pause
    exit /b 1
)

REM Display Python version
for /f "tokens=*" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
echo Found: %PYTHON_VERSION%
echo.

REM Check if automated_setup.py exists
if not exist "%~dp0automated_setup.py" (
    echo [ERROR] automated_setup.py not found in current directory
    echo.
    echo Please make sure you're running this from the ChatProxyPlatform root directory
    echo.
    pause
    exit /b 1
)

REM Run the Python script
echo Starting automated setup...
echo.
python "%~dp0automated_setup.py"

REM Capture exit code
set EXIT_CODE=%errorlevel%

echo.
if %EXIT_CODE% equ 0 (
    echo ================================================================================
    echo Setup completed successfully!
    echo ================================================================================
) else (
    echo ================================================================================
    echo Setup encountered errors. Please review the output above.
    echo ================================================================================
)

echo.
echo Press any key to exit...
pause >nul

exit /b %EXIT_CODE%
