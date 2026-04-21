@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM BHSS Remote Machine Probe and Fix
REM ============================================================================
REM Purpose: SSH into remote BHSS machine, probe state before batch operations
REM Usage: probe_and_fix_bhss.bat [machine-ip]
REM Default: ai01.bhss.edu.hk or 10.10.0.x (via WireGuard)
REM
REM Dependencies:
REM   - OpenSSH client (Windows 10+)
REM   - ~/.ssh/fleet_ed25519 private key
REM   - WireGuard VPN connection to 10.10.0.0/24
REM   - diagnose-bhss-state.ps1 on target machine

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"
set "PROBE_TARGET=%1"

if "%PROBE_TARGET%"=="" (
    set "PROBE_TARGET=ai01.bhss.edu.hk"
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "TIMESTAMP=%date:~-4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "PROBE_LOG=%LOG_DIR%\probe-bhss-remote-%TIMESTAMP%.log"

echo. >> "%PROBE_LOG%"
echo ============================================================ >> "%PROBE_LOG%"
echo  BHSS Remote Machine Probe - %TIMESTAMP% >> "%PROBE_LOG%"
echo ============================================================ >> "%PROBE_LOG%"
echo. >> "%PROBE_LOG%"
echo Target Machine: %PROBE_TARGET% >> "%PROBE_LOG%"
echo. >> "%PROBE_LOG%"

REM ──────────────────────────────────────────────────────────────
REM Step 1: Validate SSH connectivity
REM ──────────────────────────────────────────────────────────────
echo.
echo [STEP 1] Validating SSH connectivity to %PROBE_TARGET%...
echo [STEP 1] Validating SSH connectivity to %PROBE_TARGET%... >> "%PROBE_LOG%"

ssh -i "%USERPROFILE%\.ssh\fleet_ed25519" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes admin@%PROBE_TARGET% "echo SSH_OK" >nul 2>&1

if errorlevel 1 (
    echo [FAIL] Cannot SSH to %PROBE_TARGET% >> "%PROBE_LOG%"
    echo [FAIL] Cannot SSH to %PROBE_TARGET%
    echo        Verify:
    echo        - WireGuard VPN is connected (10.10.0.0/24)
    echo        - SSH key exists: %USERPROFILE%\.ssh\fleet_ed25519
    echo        - Target machine is online
    exit /b 1
) else (
    echo [OK] SSH connectivity established >> "%PROBE_LOG%"
    echo [OK] SSH connectivity established
)

REM ──────────────────────────────────────────────────────────────
REM Step 2: Collect machine identity
REM ──────────────────────────────────────────────────────────────
echo.
echo [STEP 2] Collecting remote machine identity...
echo [STEP 2] Collecting remote machine identity... >> "%PROBE_LOG%"

ssh -i "%USERPROFILE%\.ssh\fleet_ed25519" admin@%PROBE_TARGET% "hostname; wsl -- lsb_release -a 2>/dev/null || ver" 2>>"%PROBE_LOG%" | tee -a "%PROBE_LOG%"

REM ──────────────────────────────────────────────────────────────
REM Step 3: Remote Docker status check
REM ──────────────────────────────────────────────────────────────
echo.
echo [STEP 3] Checking Docker status on remote machine...
echo [STEP 3] Checking Docker status on remote machine... >> "%PROBE_LOG%"

ssh -i "%USERPROFILE%\.ssh\fleet_ed25519" admin@%PROBE_TARGET% "docker ps --format='table {{.Names}}\t{{.Status}}'" 2>>"%PROBE_LOG%" | tee -a "%PROBE_LOG%"

if errorlevel 1 (
    echo [WARN] Docker query failed - services may not be running >> "%PROBE_LOG%"
) else (
    echo [OK] Docker services responding >> "%PROBE_LOG%"
)

REM ──────────────────────────────────────────────────────────────
REM Step 4: Run remote diagnostic script
REM ──────────────────────────────────────────────────────────────
echo.
echo [STEP 4] Running remote diagnostic script...
echo [STEP 4] Running remote diagnostic script... >> "%PROBE_LOG%"

ssh -i "%USERPROFILE%\.ssh\fleet_ed25519" admin@%PROBE_TARGET% "cd /mnt/c/Users/admin/Documents/ThankGodForJesusChrist/ThankGodForChatProxyPlatform && pwsh -NoProfile -File diagnose-bhss-state.ps1" 2>>"%PROBE_LOG%" | tee -a "%PROBE_LOG%"

REM ──────────────────────────────────────────────────────────────
REM Step 5: Collect service port status
REM ──────────────────────────────────────────────────────────────
echo.
echo [STEP 5] Checking service port availability...
echo [STEP 5] Checking service port availability... >> "%PROBE_LOG%"

ssh -i "%USERPROFILE%\.ssh\fleet_ed25519" admin@%PROBE_TARGET% ^
  "powershell -NoProfile -Command \"netstat -ano 2>/dev/null ^| findstr -E '3000|3001|3082|8000|3002|27017|5432' || netstat -ano ^| grep -E '3000|3001|3082|8000|3002|27017|5432'\"" 2>>"%PROBE_LOG%" | tee -a "%PROBE_LOG%"

REM ──────────────────────────────────────────────────────────────
REM Step 6: Summary and recommendations
REM ──────────────────────────────────────────────────────────────
echo.
echo [STEP 6] Generating probe summary...
echo [STEP 6] Generating probe summary... >> "%PROBE_LOG%"
echo. >> "%PROBE_LOG%"

echo ============================================================
echo  BHSS Remote Probe Complete
echo ============================================================
echo.
echo Probe Log: %PROBE_LOG%
echo.
echo Next Steps:
echo  1. Review the probe log for issues
echo  2. If all services are running: run batch-user-create.ps1 -ComputerName %PROBE_TARGET%
echo  3. If services failed: SSH to %PROBE_TARGET% and diagnose
echo.
echo Log location: %PROBE_LOG%
echo. >> "%PROBE_LOG%"
echo Probe completed at %date% %time% >> "%PROBE_LOG%"
echo. >> "%PROBE_LOG%"

exit /b 0
