@echo off
REM ============================================
REM CSV User Management - Admin Rights Required
REM ============================================
REM Creates and deletes users from users.csv file

REM Change to the script's directory (important when run as admin)
cd /d "%~dp0"

echo ============================================
echo CSV User Management Script
echo ============================================
echo.
echo Working directory: %CD%
echo.

REM Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script requires Administrator privileges!
    echo Please right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo [OK] Running with Administrator privileges
echo.

REM Check if users.csv exists
if not exist "users.csv" (
    echo [INFO] users.csv not found. Creating from template...
    if exist "users_template.csv" (
        copy "users_template.csv" "users.csv"
        echo [SUCCESS] Created users.csv from template
        echo.
        echo Please edit users.csv with your user data and run this script again.
        echo.
        notepad users.csv
        pause
        exit /b 0
    ) else (
        echo [ERROR] Template file users_template.csv not found!
        pause
        exit /b 1
    )
)

echo [INFO] Found users.csv file
echo.

REM Install required packages (system-wide)
echo [INFO] Checking required packages...
python -c "import requests" 2>nul
if errorlevel 1 (
    echo [INFO] Installing requests package...
    pip install --quiet requests
)
echo [SUCCESS] Packages ready
echo.

REM Run the CSV management script
echo [INFO] Processing users from CSV file...
echo.
python manage_users_csv.py

echo.
echo ============================================
echo Script completed
echo Check user_management.log for details
echo ============================================
pause
