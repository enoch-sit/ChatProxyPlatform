@echo off
REM Quick launcher for configure_drives.py
REM This script ensures Python is available and runs the drive configuration tool

title ChatProxy Platform - Drive Configuration

echo.
echo Starting Drive Configuration Tool...
echo.

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo Please install Python 3.x from https://www.python.org/downloads/
    pause
    exit /b 1
)

REM Run the Python script
python configure_drives.py

REM Check exit code
if errorlevel 1 (
    echo.
    echo [ERROR] Configuration script encountered an error
    pause
    exit /b 1
)

pause
