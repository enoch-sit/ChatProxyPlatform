@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM  patch_and_migrate.bat
REM  Patches the 4 services updated in the admin-credit-UI session
REM  and backfills any pre-existing auth-service users into the
REM  accounting-service users-directory.
REM
REM  Order matters:
REM    1) accounting-service  (new endpoints; everyone else depends on it)
REM    2) auth-service        (new ensureAccountingUser hook calls accounting)
REM    3) flowise-proxy       (new users-directory passthrough)
REM    4) bridge              (UI consumes the new endpoints; rebuild bakes URL)
REM
REM  After all rebuilds:
REM    5) Backfill: list auth users vs accounting directory; call
REM       /api/users/ensure for any missing user (idempotent).
REM
REM  Required env (set BEFORE running):
REM    PATCH_TARGET=BHSS
REM    PATCH_ALLOW_ALL=1                (only required if you pass "all")
REM    FLOWISE_PROXY_URL=http://ai01.bhss.edu.hk:8000
REM
REM  Optional env:
REM    ADMIN_USERNAME=admin             (default)
REM    ADMIN_PASSWORD=admin@admin       (default; override for BHSS prod)
REM    AUTH_URL=http://localhost:3000   (default; auth-service host port)
REM    ACCOUNTING_URL=http://localhost:3001
REM    SKIP_BACKFILL=1                  (set to skip migration step)
REM ============================================================

set "ROOT=%~dp0"
set "LOG_DIR=%ROOT%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%I"
set "MASTER_LOG=%LOG_DIR%\patch-and-migrate-%TS%.log"

echo ============================================================
echo  Patch and Migrate (admin credit UI rollout)
echo ============================================================
echo Target:   %PATCH_TARGET%
echo Bridge:   %FLOWISE_PROXY_URL%
echo Log:      %MASTER_LOG%
echo Started:  %DATE% %TIME%
echo.

REM ---- Hard safety gates -------------------------------------------------
if "%PATCH_TARGET%"=="" (
  echo [FAIL] PATCH_TARGET is required. set PATCH_TARGET=BHSS
  exit /b 1
)
if /I not "%PATCH_TARGET%"=="BHSS" if /I not "%PATCH_TARGET%"=="AWS" (
  echo [FAIL] PATCH_TARGET must be BHSS or AWS. Current: %PATCH_TARGET%
  exit /b 1
)
if "%FLOWISE_PROXY_URL%"=="" (
  echo [FAIL] FLOWISE_PROXY_URL is required for the bridge rebuild.
  echo        set FLOWISE_PROXY_URL=http://ai01.bhss.edu.hk:8000
  exit /b 1
)

if "%ADMIN_USERNAME%"=="" set "ADMIN_USERNAME=admin"
if "%ADMIN_PASSWORD%"=="" set "ADMIN_PASSWORD=admin@admin"
if "%AUTH_URL%"=="" set "AUTH_URL=http://localhost:3000"
if "%ACCOUNTING_URL%"=="" set "ACCOUNTING_URL=http://localhost:3001"

call :log INFO "patch_and_migrate started; target=%PATCH_TARGET%"

REM ---- Phase 0: pre-flight git state -------------------------------------
call :log INFO "Verifying git branch is bhss"
for /f "delims=" %%B in ('git -C "%ROOT%." rev-parse --abbrev-ref HEAD') do set "BRANCH=%%B"
echo [INFO] On branch: %BRANCH%
if /I not "%BRANCH%"=="bhss" (
  if /I not "%BRANCH%"=="release/aws" (
    echo [WARN] You are on branch '%BRANCH%', not bhss. Continuing anyway.
    call :log WARN "Branch is %BRANCH% (expected bhss)"
  )
)
for /f "delims=" %%C in ('git -C "%ROOT%." rev-parse --short HEAD') do set "COMMIT=%%C"
call :log INFO "Commit %COMMIT%"

REM ---- Phase 1: patch each service in dependency order -------------------
REM Use 'full' (not 'auto') because patch.ps1 auto-detect skips $changedFiles
REM when -Service is specified, which causes 'quick' mode (no image rebuild)
REM and our new .ts/.py code never reaches the running container.
call :patch_one accounting-service full || exit /b 1
call :patch_one auth-service       full || exit /b 1
call :patch_one flowise-proxy      full || exit /b 1
call :patch_one bridge             full || exit /b 1

REM ---- Phase 2: backfill missing accounting users ------------------------
if /I "%SKIP_BACKFILL%"=="1" (
  call :log WARN "SKIP_BACKFILL=1; skipping users-directory backfill"
  echo [WARN] Skipping backfill as requested.
  goto :done
)

call :log INFO "Running users-directory backfill"
echo.
echo ============================================================
echo  Backfill: ensure pre-existing auth users exist in accounting
echo ============================================================

REM Run the backfill via PowerShell (uses host curl-equivalent Invoke-RestMethod)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\backfill-accounting-users.ps1" ^
    -AuthUrl "%AUTH_URL%" ^
    -AccountingUrl "%ACCOUNTING_URL%" ^
    -AdminUsername "%ADMIN_USERNAME%" ^
    -AdminPassword "%ADMIN_PASSWORD%" ^
    -LogFile "%MASTER_LOG%"
if errorlevel 1 (
  call :log ERROR "Backfill failed (non-fatal; services already patched)"
  echo [FAIL] Backfill step reported errors. Services are patched; review the log:
  echo        %MASTER_LOG%
  exit /b 2
)
call :log OK "Backfill completed"

:done
echo.
echo ============================================================
echo [OK] Patch and migrate completed.
echo      Log: %MASTER_LOG%
echo ============================================================
exit /b 0


:patch_one
REM %1 = service name, %2 = mode
set "SVC=%~1"
set "PMODE=%~2"
echo.
echo ============================================================
echo  Patching service: %SVC%  (mode=%PMODE%)
echo ============================================================
call :log INFO "patch %SVC% mode=%PMODE%"

call "%ROOT%patch-windows-workstation.bat" %SVC% %PMODE%
if errorlevel 1 (
  call :log ERROR "patch-windows-workstation.bat failed for %SVC%"
  echo [FAIL] Service patch failed: %SVC%
  exit /b 1
)
call :log OK "%SVC% patched"
exit /b 0

:log
set "LVL=%~1"
set "MSG=%~2"
echo [%LVL%] %MSG%
>> "%MASTER_LOG%" echo [%DATE% %TIME%] [%LVL%] %MSG%
exit /b 0
