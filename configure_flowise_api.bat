@echo off
REM Configure Flowise API Key
REM Author: Enoch Sit
REM License: MIT

echo.
echo ============================================================
echo    Flowise API Key Configuration
echo ============================================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo.
    echo Please install Python 3.8 or higher from:
    echo https://www.python.org/downloads/
    echo.
    echo Make sure to check "Add Python to PATH" during installation
    pause
    exit /b 1
)

REM Get Python version
for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
echo [INFO] Found Python %PYTHON_VERSION%
echo.

REM Run the Python script
echo [INFO] Starting configuration script...
echo.
python configure_flowise_api.py

REM Check if the script executed successfully
if errorlevel 1 (
    echo.
    echo ============================================================
    echo [ERROR] Configuration failed
    echo ============================================================
    echo.
    echo Please check the error messages above
    pause
    exit /b 1
) else (
    echo.
    echo ============================================================
    echo [SUCCESS] Configuration completed successfully!
    echo ============================================================
    echo.
    pause
    exit /b 0
)
