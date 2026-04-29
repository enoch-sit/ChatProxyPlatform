@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM  probe_and_patch.bat
REM  One-shot patch wrapper for a LOCAL Windows workstation
REM  (e.g. aidcec / DESKTOP-AF69OPD). Not for BHSS - BHSS uses
REM  patch_and_migrate.bat with its protected-file logic.
REM
REM  Steps:
REM    0) Pre-probe + sanity checks
REM    1) Patch services in dependency order with FULL mode
REM         accounting-service -> auth-service ->
REM         flowise-proxy      -> bridge
REM    2) Backfill missing accounting users
REM    3) Post-probe
REM    4) Summary
REM
REM  Default env (override before running if needed):
REM    ADMIN_USERNAME=admin
REM    ADMIN_PASSWORD=admin@admin
REM    AUTH_URL=http://localhost:3000
REM    ACCOUNTING_URL=http://localhost:3001
REM    FLOWISE_PROXY_URL=http://localhost:8000
REM    SKIP_BACKFILL=1   (optional - skip step 2)
REM    SKIP_PRE_PROBE=1  (optional - skip step 0 probe)
REM    SKIP_POST_PROBE=1 (optional - skip step 3 probe)
REM ============================================================

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%I"
set "MASTER_LOG=%LOG_DIR%\probe-and-patch-%TS%.log"

if "%ADMIN_USERNAME%"==""    set "ADMIN_USERNAME=admin"
if "%ADMIN_PASSWORD%"==""    set "ADMIN_PASSWORD=admin@admin"
if "%AUTH_URL%"==""          set "AUTH_URL=http://localhost:3000"
if "%ACCOUNTING_URL%"==""    set "ACCOUNTING_URL=http://localhost:3001"
if "%FLOWISE_PROXY_URL%"=="" set "FLOWISE_PROXY_URL=http://localhost:8000"

REM patch-windows-workstation.bat checks PATCH_TARGET; LOCAL = local workstation
set "PATCH_TARGET=LOCAL"

echo ============================================================
echo  ChatProxy Local Probe + Patch
echo ============================================================
echo Host:               %COMPUTERNAME%
echo Repo:               %ROOT%
echo Master log:         %MASTER_LOG%
echo AUTH_URL:           %AUTH_URL%
echo ACCOUNTING_URL:     %ACCOUNTING_URL%
echo FLOWISE_PROXY_URL:  %FLOWISE_PROXY_URL%
echo Started:            %DATE% %TIME%
echo.

call :log INFO "probe_and_patch started on %COMPUTERNAME%"

REM ---- Sanity gates ------------------------------------------------------
docker info >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Docker daemon is not running. Start Docker Desktop and retry.
    call :log ERROR "Docker not running"
    exit /b 1
)

if not exist "%ROOT%\patch-windows-workstation.bat" (
    echo [FAIL] patch-windows-workstation.bat missing. git pull first.
    call :log ERROR "patch-windows-workstation.bat missing"
    exit /b 1
)
if not exist "%ROOT%\patch.ps1" (
    echo [FAIL] patch.ps1 missing. git pull first.
    call :log ERROR "patch.ps1 missing"
    exit /b 1
)
if not exist "%ROOT%\check-patch-drift.ps1" (
    echo [FAIL] check-patch-drift.ps1 missing. git pull first.
    call :log ERROR "check-patch-drift.ps1 missing"
    exit /b 1
)

REM ---- Branch sanity (warn-only) ----------------------------------------
for /f "delims=" %%B in ('git -C "%ROOT%" rev-parse --abbrev-ref HEAD 2^>nul') do set "BRANCH=%%B"
echo [INFO] Git branch: %BRANCH%
call :log INFO "branch=%BRANCH%"
if /I not "%BRANCH%"=="deploy/localdeploy" (
    echo [WARN] Expected branch deploy/localdeploy but on '%BRANCH%'. Continuing.
    call :log WARN "branch mismatch %BRANCH%"
)

REM ---- Phase 0: pre-probe -----------------------------------------------
if /I "%SKIP_PRE_PROBE%"=="1" (
    echo [WARN] SKIP_PRE_PROBE=1, skipping pre-patch probe.
) else (
    echo.
    echo ============================================================
    echo  Phase 0: Pre-patch probe
    echo ============================================================
    if exist "%ROOT%\probe_state.bat" (
        call "%ROOT%\probe_state.bat" >nul
        if errorlevel 1 (
            echo [WARN] probe_state.bat returned non-zero, continuing.
            call :log WARN "probe_state.bat non-zero"
        )
    ) else (
        echo [INFO] probe_state.bat not present, skipping descriptive probe.
    )
)

REM ---- Phase 1: patch services in order --------------------------------
echo.
echo ============================================================
echo  Phase 1: Patch services (full mode)
echo ============================================================

call :patch_one accounting-service full || goto :patch_failed
call :patch_one auth-service       full || goto :patch_failed
call :patch_one flowise-proxy      full || goto :patch_failed
call :patch_one bridge             full || goto :patch_failed

REM ---- Phase 2: backfill ------------------------------------------------
if /I "%SKIP_BACKFILL%"=="1" (
    call :log WARN "SKIP_BACKFILL=1; skipping backfill"
    echo [WARN] Skipping accounting backfill as requested.
) else (
    echo.
    echo ============================================================
    echo  Phase 2: Backfill missing accounting users
    echo ============================================================
    if not exist "%ROOT%\scripts\backfill-accounting-users.ps1" (
        echo [WARN] scripts\backfill-accounting-users.ps1 missing, skipping.
        call :log WARN "backfill script missing"
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\backfill-accounting-users.ps1" ^
            -AuthUrl "%AUTH_URL%" ^
            -AccountingUrl "%ACCOUNTING_URL%" ^
            -AdminUsername "%ADMIN_USERNAME%" ^
            -AdminPassword "%ADMIN_PASSWORD%" ^
            -LogFile "%MASTER_LOG%"
        if errorlevel 1 (
            echo [WARN] Backfill reported errors. Services are patched; review %MASTER_LOG%.
            call :log WARN "backfill non-zero"
        ) else (
            call :log OK "backfill completed"
        )
    )
)

REM ---- Phase 3: post-probe ---------------------------------------------
if /I "%SKIP_POST_PROBE%"=="1" (
    echo [WARN] SKIP_POST_PROBE=1, skipping post-patch probe.
) else (
    echo.
    echo ============================================================
    echo  Phase 3: Post-patch probe
    echo ============================================================
    if exist "%ROOT%\probe_state.bat" (
        call "%ROOT%\probe_state.bat" >nul
    )
)

REM ---- Phase 4: summary ------------------------------------------------
echo.
echo ============================================================
echo  [OK] probe_and_patch completed
echo ============================================================
echo Master log: %MASTER_LOG%
echo Latest probe: %LOG_DIR%\probe_state-^<latest^>.txt
echo.
echo Verify in browser:
echo   - Hard reload http://localhost:3082/admin (Ctrl-F5)
echo   - Network tab: bundle filename should differ from before patch
echo   - Open a student's chat history: AI bubbles show response text,
echo     role labels show Student / AI correctly
echo.
call :log OK "probe_and_patch finished"
exit /b 0


:patch_failed
echo.
echo ============================================================
echo [FAIL] Patch step failed. See %MASTER_LOG%
echo ============================================================
call :log ERROR "patch step failed"
exit /b 1


:patch_one
REM %1 = service name, %2 = mode
set "SVC=%~1"
set "PMODE=%~2"
echo.
echo ------------------------------------------------------------
echo  Patching %SVC% (mode=%PMODE%)
echo ------------------------------------------------------------
call :log INFO "patch %SVC% mode=%PMODE%"

call "%ROOT%\patch-windows-workstation.bat" %SVC% %PMODE%
if errorlevel 1 (
    call :log ERROR "patch-windows-workstation.bat failed for %SVC%"
    echo [FAIL] %SVC% patch failed.
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
