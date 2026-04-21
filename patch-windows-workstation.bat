@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Safe Windows wrapper around patch.ps1 for production workstation patching.
REM Usage: patch-windows-workstation.bat [service] [mode]

set "ROOT=%~dp0"
set "LOG_DIR=%ROOT%logs"
set "STATE_FILE=%ROOT%logs\probe-state-latest.env"
set "SERVICE=%~1"
set "MODE=%~2"

if "%SERVICE%"=="" set "SERVICE=all"
if "%MODE%"=="" set "MODE=auto"

REM HARD SAFETY: require explicit patch target
if "%PATCH_TARGET%"=="" (
  echo [FAIL] PATCH_TARGET is required. Set PATCH_TARGET=BHSS or PATCH_TARGET=AWS before patching.
  echo        Example: set PATCH_TARGET=BHSS
  exit /b 1
)

if /I not "%PATCH_TARGET%"=="BHSS" if /I not "%PATCH_TARGET%"=="AWS" (
  echo [FAIL] PATCH_TARGET must be BHSS or AWS. Current: %PATCH_TARGET%
  exit /b 1
)

if /I "%PATCH_TARGET%"=="BHSS" (
  echo %COMPUTERNAME% | find /I "BHSS" >nul
  if errorlevel 1 (
    echo [FAIL] PATCH_TARGET=BHSS but machine name does not look like BHSS: %COMPUTERNAME%
    exit /b 1
  )
)

REM HARD SAFETY: prevent broad all-service patch unless explicitly confirmed
if /I "%SERVICE%"=="all" (
  if /I not "%PATCH_ALLOW_ALL%"=="1" (
    echo [FAIL] SERVICE=all requires PATCH_ALLOW_ALL=1 confirmation.
    echo        Example: set PATCH_ALLOW_ALL=1
    exit /b 1
  )
)

REM Bridge UI builds bake API URL at build time
if /I "%SERVICE%"=="bridge" (
  if "%FLOWISE_PROXY_URL%"=="" (
    echo [FAIL] FLOWISE_PROXY_URL is required when patching bridge.
    echo        Example: set FLOWISE_PROXY_URL=http://ai01.bhss.edu.hk:8000
    exit /b 1
  )
  echo [INFO] Bridge build target: %FLOWISE_PROXY_URL%
)

echo [INFO] Patch guard: PATCH_TARGET=%PATCH_TARGET%  SERVICE=%SERVICE%  MODE=%MODE%

REM Create timestamp for log file
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%I"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "LOG_FILE=%LOG_DIR%\patch-workstation-%TS%.log"

echo ============================================================
echo  Safe Production Patch Wrapper
echo ============================================================
echo Service: %SERVICE%
echo Mode:    %MODE%
echo Log:     %LOG_FILE%
echo.

call :log INFO "Wrapper started"

call :log INFO "Running pre-patch machine probe"
call "%ROOT%probe-machine-state.bat" >nul 2>&1
if errorlevel 1 (
  call :log ERROR "Probe failed; aborting patch"
  echo [FAIL] Probe failed. Patch aborted.
  exit /b 1
)

if not exist "%STATE_FILE%" (
  call :log ERROR "Probe state file missing: %STATE_FILE%"
  echo [FAIL] Probe state file not found. Patch aborted.
  exit /b 1
)
call :log OK "Loaded pre-patch state file"

call :log INFO "Executing patch.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%patch.ps1" -Service "%SERVICE%" -Mode "%MODE%"
if errorlevel 1 (
  call :log ERROR "patch.ps1 failed"
  echo [FAIL] patch.ps1 failed.
  exit /b 1
)
call :log OK "patch.ps1 completed"

call :log INFO "Running post-patch probe"
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS2=%%I"
set "POST_STATE_FILE=%LOG_DIR%\probe-state-postpatch-%TS2%.env"
call "%ROOT%probe-machine-state.bat" "%POST_STATE_FILE%" >nul 2>&1
if errorlevel 1 (
  call :log ERROR "Post-patch probe failed"
  echo [FAIL] Post-patch probe failed.
  exit /b 1
)
call :log OK "Post-patch probe completed"

call :log INFO "Comparing pre/post state for drift"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%check-patch-drift.ps1" -PreFile "%STATE_FILE%" -PostFile "%POST_STATE_FILE%" >nul 2>&1
if errorlevel 1 (
  call :log ERROR "Forbidden drift detected"
  echo [FAIL] Password or data drift detected. Patch aborted.
  exit /b 1
)
call :log OK "No password/data drift detected"

call :log OK "Patch completed successfully"
echo [OK] Patch completed safely with no password or data changes.
exit /b 0

:log
set "LEVEL=%~1"
set "MSG=%~2"
echo [%LEVEL%] %MSG%
if exist "%LOG_FILE%" (
  >> "%LOG_FILE%" echo [%LEVEL%] %MSG%
)
exit /b 0
