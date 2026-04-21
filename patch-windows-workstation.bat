@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Safe Windows wrapper around patch.ps1 for production workstation patching.
REM It enforces comprehensive pre/post probe checks and blocks password/data drift.
REM Usage: patch-windows-workstation.bat [service] [mode]

set "ROOT=%~dp0"
set "LOG_DIR=%ROOT%logs"
set "STATE_FILE=%ROOT%logs\probe-state-latest.env"
set "POST_STATE_FILE=%ROOT%logs\probe-state-postpatch-%RANDOM%.env"
set "SERVICE=%~1"
set "MODE=%~2"
if "%SERVICE%"=="" set "SERVICE=all"
if "%MODE%"=="" set "MODE=auto"

REM Bridge UI builds bake API URL at build time; force explicit target to avoid wrong domain bake-in.
if /I "%SERVICE%"=="bridge" (
  if "%FLOWISE_PROXY_URL%"=="" (
    echo [FAIL] FLOWISE_PROXY_URL is required when patching bridge.
    echo        Example for BHSS: set FLOWISE_PROXY_URL=https://ai01.bhss.edu.hk
    exit /b 1
  )
  echo [INFO] Bridge build target FLOWISE_PROXY_URL=%FLOWISE_PROXY_URL%
)

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
call "%ROOT%probe-machine-state.bat"
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
call :log OK "Loaded pre-patch state file: %STATE_FILE%"

call :log INFO "Executing patch.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%patch.ps1" -Service "%SERVICE%" -Mode "%MODE%"
if errorlevel 1 (
  call :log ERROR "patch.ps1 failed"
  echo [FAIL] patch.ps1 failed.
  exit /b 1
)
call :log OK "patch.ps1 completed"

set "ENV_FILE=%ROOT%flowise-proxy-service-py\.env"
if not exist "%ENV_FILE%" (
  call :log ERROR "Missing env file after patch: %ENV_FILE%"
  echo [FAIL] flowise proxy env file missing after patch.
  exit /b 1
)

call :log INFO "Running post-patch comprehensive probe"
call "%ROOT%probe-machine-state.bat" "%POST_STATE_FILE%"
if errorlevel 1 (
  call :log ERROR "Post-patch probe failed"
  echo [FAIL] Post-patch probe failed.
  exit /b 1
)

call :log INFO "Comparing pre/post state for forbidden drift (passwords/data)"
powershell -NoProfile -Command "function Parse-State([string]$p){ $m=@{}; if(Test-Path $p){ Get-Content $p | ForEach-Object { if($_ -match '^(?<k>[^=]+)=(?<v>.*)$'){ $m[$matches.k]=$matches.v } } }; return $m }; $pre=Parse-State('%STATE_FILE%'); $post=Parse-State('%POST_STATE_FILE%'); $keys=@('FLOWISE_API_KEY_SHA256','FLOWISE_SECRETKEY_OVERWRITE_SHA256','PROXY_MONGO_PASSWORD_SHA256','PROXY_JWT_ACCESS_SECRET_SHA256','PROXY_JWT_REFRESH_SECRET_SHA256','AUTH_MONGO_INITDB_ROOT_PASSWORD_SHA256','AUTH_JWT_ACCESS_SECRET_SHA256','AUTH_JWT_REFRESH_SECRET_SHA256','ACCOUNTING_DB_PASSWORD_SHA256','ACCOUNTING_POSTGRES_PASSWORD_SHA256','DATA_AUTH_USERS_COUNT','DATA_PROXY_OBJECTS_COUNT','DATA_FLOWISE_PG_EST_ROWS','DATA_ACCOUNTING_PG_EST_ROWS'); $diff=@(); foreach($k in $keys){ $a = if($pre.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace($pre[$k])) { $pre[$k] } else { '__MISSING__' }; $b = if($post.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace($post[$k])) { $post[$k] } else { '__MISSING__' }; if($a -ne $b){ $diff += ('{0}: PRE={1} POST={2}' -f $k,$a,$b) } }; if($diff.Count -gt 0){ $diff | ForEach-Object { Write-Host $_ }; exit 1 } else { exit 0 }"
if errorlevel 1 (
  call :log ERROR "Forbidden drift detected: password/data state changed"
  echo [FAIL] Password or data drift detected. Patch aborted as requested.
  echo [FAIL] See state files:
  echo        PRE:  %STATE_FILE%
  echo        POST: %POST_STATE_FILE%
  exit /b 1
)
call :log OK "No password/data drift detected"

call :log INFO "Checking Flowise container health endpoint"
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:3002/api/v1/ping' -UseBasicParsing -TimeoutSec 10; if ($r.StatusCode -eq 200) { exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
  call :log ERROR "Flowise health endpoint check failed"
  echo [FAIL] Flowise health check failed after patch.
  exit /b 1
)
call :log OK "Flowise health endpoint reachable"

call :log OK "Safe patch wrapper completed successfully"
echo [OK] Patch completed safely with no password or data changes.
exit /b 0

:log
set "LEVEL=%~1"
set "MSG=%~2"
echo [%LEVEL%] %MSG%
>> "%LOG_FILE%" echo [%LEVEL%] %MSG%
exit /b 0
