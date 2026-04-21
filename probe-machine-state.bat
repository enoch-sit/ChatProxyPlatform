@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Comprehensive Windows workstation probe.
REM Exit code: 0 = safe to patch, 1 = abort.
REM Usage:
REM   probe-machine-state.bat
REM   probe-machine-state.bat "C:\path\custom-state.env"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%I"
set "LOG_FILE=%LOG_DIR%\probe-state-%TS%.log"

set "STATE_FILE=%~1"
if "%STATE_FILE%"=="" set "STATE_FILE=%LOG_DIR%\probe-state-latest.env"

set "PROBE_FAIL=0"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo ============================================================
echo  ChatProxy Windows Comprehensive Workstation Probe
echo ============================================================
echo Log:   %LOG_FILE%
echo State: %STATE_FILE%
echo.

call :log INFO "Probe started"

call :check_docker || goto :hard_fail
call :collect_git_state || goto :hard_fail
call :collect_container_state || goto :hard_fail
call :check_flowise_volumes || goto :hard_fail
call :collect_endpoint_state || goto :hard_fail
call :collect_secret_fingerprints || goto :hard_fail
call :collect_data_fingerprints || goto :hard_fail
call :write_state_file || goto :hard_fail

call :log OK "Comprehensive probe completed"
echo [OK] Machine state probe completed. State file written.
exit /b 0

:check_docker
call :log INFO "Checking Docker daemon"
docker info >nul 2>&1
if errorlevel 1 (
  call :log ERROR "Docker is not running"
  echo [FAIL] Docker is not running.
  exit /b 1
)
call :log OK "Docker daemon running"
exit /b 0

:collect_git_state
call :log INFO "Collecting Git branch/commit state"
set "GIT_BRANCH="
set "GIT_HEAD="
set "GIT_HEAD_SHORT="
set "GIT_UPSTREAM="
set "GIT_UPSTREAM_HEAD="
set "GIT_DIRTY_COUNT=0"

for /f "usebackq delims=" %%A in (`git -C "%ROOT%" rev-parse --abbrev-ref HEAD 2^>nul`) do set "GIT_BRANCH=%%A"
for /f "usebackq delims=" %%A in (`git -C "%ROOT%" rev-parse HEAD 2^>nul`) do set "GIT_HEAD=%%A"
for /f "usebackq delims=" %%A in (`git -C "%ROOT%" rev-parse --short HEAD 2^>nul`) do set "GIT_HEAD_SHORT=%%A"
for /f "usebackq delims=" %%A in (`git -C "%ROOT%" rev-parse --abbrev-ref --symbolic-full-name @{u} 2^>nul`) do set "GIT_UPSTREAM=%%A"
if defined GIT_UPSTREAM (
  for /f "usebackq delims=" %%A in (`git -C "%ROOT%" rev-parse "%GIT_UPSTREAM%" 2^>nul`) do set "GIT_UPSTREAM_HEAD=%%A"
)
for /f %%A in ('powershell -NoProfile -Command "(git -C '%ROOT%' status --porcelain 2^> $null | Measure-Object).Count"') do set "GIT_DIRTY_COUNT=%%A"

if not defined GIT_BRANCH (
  call :log ERROR "Unable to read git branch"
  exit /b 1
)
if not defined GIT_HEAD (
  call :log ERROR "Unable to read git HEAD commit"
  exit /b 1
)

call :log OK "Git branch: %GIT_BRANCH%"
call :log OK "Git commit: %GIT_HEAD_SHORT%"
exit /b 0

:collect_container_state
call :log INFO "Collecting container state"
set "C_FLOWISE_RUNNING=0"
set "C_FLOWISE_POSTGRES_RUNNING=0"
set "C_FLOWISE_PROXY_RUNNING=0"
set "C_AUTH_SERVICE_RUNNING=0"
set "C_ACCOUNTING_SERVICE_RUNNING=0"
set "C_BRIDGE_RUNNING=0"

for /f "usebackq delims=" %%A in (`docker ps --filter "name=^flowise$" --format "{{.Names}}"`) do set "C_FLOWISE_RUNNING=1"
for /f "usebackq delims=" %%A in (`docker ps --filter "name=^flowise-postgres$" --format "{{.Names}}"`) do set "C_FLOWISE_POSTGRES_RUNNING=1"
for /f "usebackq delims=" %%A in (`docker ps --filter "name=^flowise-proxy$" --format "{{.Names}}"`) do set "C_FLOWISE_PROXY_RUNNING=1"
for /f "usebackq delims=" %%A in (`docker ps --filter "name=^auth-service$" --format "{{.Names}}"`) do set "C_AUTH_SERVICE_RUNNING=1"
for /f "usebackq delims=" %%A in (`docker ps --filter "name=^accounting-service$" --format "{{.Names}}"`) do set "C_ACCOUNTING_SERVICE_RUNNING=1"
for /f "usebackq delims=" %%A in (`docker ps --filter "name=^bridge$" --format "{{.Names}}"`) do set "C_BRIDGE_RUNNING=1"

if "%C_FLOWISE_RUNNING%"=="0" (
  call :log ERROR "Flowise container is not running"
  echo [FAIL] Flowise container is not running.
  exit /b 1
)

if "%C_FLOWISE_PROXY_RUNNING%"=="0" (
  call :log WARN "flowise-proxy container is not running"
)
if "%C_AUTH_SERVICE_RUNNING%"=="0" (
  call :log WARN "auth-service container is not running"
)
if "%C_ACCOUNTING_SERVICE_RUNNING%"=="0" (
  call :log WARN "accounting-service container is not running"
)
if "%C_BRIDGE_RUNNING%"=="0" (
  call :log WARN "bridge container is not running"
)

call :log OK "Container state collected"
exit /b 0

:check_flowise_volumes
call :log INFO "Checking Flowise volumes"
set "V_FLOWISE_DATA_PRESENT=0"
set "V_FLOWISE_POSTGRES_PRESENT=0"

for /f "usebackq delims=" %%V in (`docker volume ls --format "{{.Name}}" ^| findstr /i "flowise_data"`) do set "V_FLOWISE_DATA_PRESENT=1"
for /f "usebackq delims=" %%V in (`docker volume ls --format "{{.Name}}" ^| findstr /i "postgres_data"`) do set "V_FLOWISE_POSTGRES_PRESENT=1"

if "%V_FLOWISE_DATA_PRESENT%"=="0" (
  call :log ERROR "Flowise data volume not found"
  echo [FAIL] Flowise data volume not found.
  exit /b 1
)
if "%V_FLOWISE_POSTGRES_PRESENT%"=="0" (
  call :log ERROR "Flowise postgres volume not found"
  echo [FAIL] Flowise postgres volume not found.
  exit /b 1
)

call :log OK "Flowise volumes are present"
exit /b 0

:collect_endpoint_state
call :log INFO "Collecting endpoint health state"
set "E_FLOWISE_HTTP=0"
set "E_PROXY_HTTP=0"
set "E_AUTH_HTTP=0"
set "E_ACCOUNTING_HTTP=0"

REM Single PowerShell spawn checks all 4 endpoints in parallel (saves ~1.5s vs 4 serial spawns)
set "EP_TMP=%TEMP%\probe_ep_%RANDOM%.txt"
del "%EP_TMP%" 2>nul
powershell -NoProfile -Command "$t='%EP_TMP%'; $eps=@( @{k='E_FLOWISE_HTTP';u='http://localhost:3002/api/v1/ping'}, @{k='E_PROXY_HTTP';u='http://localhost:8000/health'}, @{k='E_AUTH_HTTP';u='http://localhost:3000/health'}, @{k='E_ACCOUNTING_HTTP';u='http://localhost:3001/health'} ); $jobs=$eps | ForEach-Object { $ep=$_; Start-Job -ScriptBlock { param($u) try{(Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 5).StatusCode}catch{0} } -ArgumentList $ep.u | Add-Member -NotePropertyName key -NotePropertyValue $ep.k -PassThru }; $results=$jobs | ForEach-Object { $r=Receive-Job $_ -Wait; Remove-Job $_; '{0}={1}' -f $_.key,$r }; $results | Set-Content $t"
if exist "%EP_TMP%" (
  for /f "usebackq tokens=1,* delims==" %%K in ("%EP_TMP%") do set "%%K=%%L"
  del "%EP_TMP%" 2>nul
)

if not "%E_FLOWISE_HTTP%"=="200" (
  call :log ERROR "Flowise endpoint unhealthy (HTTP %E_FLOWISE_HTTP%)"
  exit /b 1
)

if not "%E_PROXY_HTTP%"=="200" call :log WARN "flowise-proxy health not OK (HTTP %E_PROXY_HTTP%)"
if not "%E_AUTH_HTTP%"=="200" call :log WARN "auth-service health not OK (HTTP %E_AUTH_HTTP%)"
if not "%E_ACCOUNTING_HTTP%"=="200" call :log WARN "accounting-service health not OK (HTTP %E_ACCOUNTING_HTTP%)"

call :log OK "Endpoint health state collected"
exit /b 0

:collect_secret_fingerprints
call :log INFO "Collecting secret/password fingerprints (no plaintext secrets stored)"
set "FP_FLOWISE_API_KEY_SHA256="
set "FP_PROXY_MONGO_PASSWORD_SHA256="
set "FP_PROXY_JWT_ACCESS_SECRET_SHA256="
set "FP_PROXY_JWT_REFRESH_SECRET_SHA256="
set "FP_FLOWISE_SECRETKEY_OVERWRITE_SHA256="
set "FP_AUTH_MONGO_INITDB_ROOT_PASSWORD_SHA256="
set "FP_AUTH_JWT_ACCESS_SECRET_SHA256="
set "FP_AUTH_JWT_REFRESH_SECRET_SHA256="
set "FP_ACCOUNTING_DB_PASSWORD_SHA256="
set "FP_ACCOUNTING_POSTGRES_PASSWORD_SHA256="

REM Single PowerShell spawn reads all 10 secrets at once (saves ~4s vs 10 serial spawns)
set "FP_TMP=%TEMP%\probe_fp_%RANDOM%.txt"
del "%FP_TMP%" 2>nul
powershell -NoProfile -Command "$r='%ROOT%'; $t='%FP_TMP%'; function gh($p,$k){ if(Test-Path $p){ $l=Get-Content $p | Where-Object{$_ -match ('^'+[regex]::Escape($k)+'=')} | Select-Object -First 1; if($l){ $v=$l.Substring($l.IndexOf('=')+1); $s=[System.Security.Cryptography.SHA256]::Create(); $b=[System.Text.Encoding]::UTF8.GetBytes($v); return ($s.ComputeHash($b)|ForEach-Object{$_.ToString('x2')}) -join '' } }; return '' }; @( 'FP_FLOWISE_API_KEY_SHA256='+(gh \"$r\flowise-proxy-service-py\.env\" 'FLOWISE_API_KEY'), 'FP_PROXY_MONGO_PASSWORD_SHA256='+(gh \"$r\flowise-proxy-service-py\.env\" 'MONGO_PASSWORD'), 'FP_PROXY_JWT_ACCESS_SECRET_SHA256='+(gh \"$r\flowise-proxy-service-py\.env\" 'JWT_ACCESS_SECRET'), 'FP_PROXY_JWT_REFRESH_SECRET_SHA256='+(gh \"$r\flowise-proxy-service-py\.env\" 'JWT_REFRESH_SECRET'), 'FP_FLOWISE_SECRETKEY_OVERWRITE_SHA256='+(gh \"$r\flowise\.env\" 'FLOWISE_SECRETKEY_OVERWRITE'), 'FP_AUTH_MONGO_INITDB_ROOT_PASSWORD_SHA256='+(gh \"$r\auth-service\.env\" 'MONGO_INITDB_ROOT_PASSWORD'), 'FP_AUTH_JWT_ACCESS_SECRET_SHA256='+(gh \"$r\auth-service\.env\" 'JWT_ACCESS_SECRET'), 'FP_AUTH_JWT_REFRESH_SECRET_SHA256='+(gh \"$r\auth-service\.env\" 'JWT_REFRESH_SECRET'), 'FP_ACCOUNTING_DB_PASSWORD_SHA256='+(gh \"$r\accounting-service\.env\" 'DB_PASSWORD'), 'FP_ACCOUNTING_POSTGRES_PASSWORD_SHA256='+(gh \"$r\accounting-service\.env\" 'POSTGRES_PASSWORD') ) | Set-Content $t"

if not exist "%FP_TMP%" (
  call :log ERROR "Secret fingerprint collection failed - temp file not written"
  exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%K in ("%FP_TMP%") do set "%%K=%%L"
del "%FP_TMP%" 2>nul

if not defined FP_FLOWISE_API_KEY_SHA256 (
  call :log ERROR "FLOWISE_API_KEY fingerprint missing"
  exit /b 1
)

call :log OK "Secret/password fingerprints collected"
exit /b 0

:collect_data_fingerprints
call :log INFO "Collecting data fingerprints (counts only)"
set "DATA_AUTH_USERS_COUNT="
set "DATA_PROXY_OBJECTS_COUNT="
set "DATA_FLOWISE_PG_EST_ROWS="
set "DATA_ACCOUNTING_PG_EST_ROWS="

REM Use a single top-level PowerShell call writing to a temp file.
REM This avoids cmd's ( ) block-matching bug with ) inside for/f inside if blocks.
set "DF_TMP=%TEMP%\probe_df_%RANDOM%.txt"
del "%DF_TMP%" 2>nul

powershell -NoProfile -Command "$f='%DF_TMP%'; $r=@('','','',''); if ('%C_AUTH_SERVICE_RUNNING%' -eq '1') { try { $v=docker exec mongodb-auth mongosh --quiet --eval 'db.getSiblingDB(''auth_db'').users.estimatedDocumentCount()' 2>$null; if ($LASTEXITCODE -eq 0 -and $v) { $r[0]=($v|Select-Object -Last 1).ToString().Trim() } } catch {} }; if ('%C_FLOWISE_PROXY_RUNNING%' -eq '1') { try { $v=docker exec mongodb-proxy mongosh --quiet --eval 'db.getSiblingDB(''flowise_proxy'').stats().objects' 2>$null; if ($LASTEXITCODE -eq 0 -and $v) { $r[1]=($v|Select-Object -Last 1).ToString().Trim() } } catch {} }; if ('%C_FLOWISE_POSTGRES_RUNNING%' -eq '1') { try { $v=docker exec flowise-postgres psql -U flowiseuser -d flowise -t -A -c 'SELECT COALESCE(SUM(n_live_tup)::bigint,0) FROM pg_stat_user_tables;' 2>$null; if ($LASTEXITCODE -eq 0 -and $v) { $r[2]=($v|Select-Object -Last 1).ToString().Trim() } } catch {} }; if ('%C_ACCOUNTING_SERVICE_RUNNING%' -eq '1') { try { $v=docker exec postgres-accounting psql -U postgres -d accounting_db -t -A -c 'SELECT COALESCE(SUM(n_live_tup)::bigint,0) FROM pg_stat_user_tables;' 2>$null; if ($LASTEXITCODE -eq 0 -and $v) { $r[3]=($v|Select-Object -Last 1).ToString().Trim() } } catch {} }; @(\"DATA_AUTH_USERS_COUNT=$($r[0])\",\"DATA_PROXY_OBJECTS_COUNT=$($r[1])\",\"DATA_FLOWISE_PG_EST_ROWS=$($r[2])\",\"DATA_ACCOUNTING_PG_EST_ROWS=$($r[3])\") | Set-Content $f"

if not exist "%DF_TMP%" (
  call :log ERROR "Data fingerprint collection failed - temp file not written"
  exit /b 1
)
for /f "usebackq tokens=1,* delims==" %%K in ("%DF_TMP%") do set "%%K=%%L"
del "%DF_TMP%" 2>nul

if "%C_FLOWISE_POSTGRES_RUNNING%"=="1" if not defined DATA_FLOWISE_PG_EST_ROWS (
  call :log ERROR "Failed to capture Flowise postgres data fingerprint"
  exit /b 1
)

if "%C_AUTH_SERVICE_RUNNING%"=="1" if not defined DATA_AUTH_USERS_COUNT (
  call :log WARN "Could not capture auth users count"
)
if "%C_FLOWISE_PROXY_RUNNING%"=="1" if not defined DATA_PROXY_OBJECTS_COUNT (
  call :log WARN "Could not capture flowise-proxy Mongo objects count"
)
if "%C_ACCOUNTING_SERVICE_RUNNING%"=="1" if not defined DATA_ACCOUNTING_PG_EST_ROWS (
  call :log WARN "Could not capture accounting postgres data fingerprint"
)

call :log OK "Data fingerprints collected"
exit /b 0

:write_state_file
call :log INFO "Writing comprehensive state file"
> "%STATE_FILE%" (
  echo TS=%TS%
  echo ROOT=%ROOT%
  echo GIT_BRANCH=%GIT_BRANCH%
  echo GIT_HEAD=%GIT_HEAD%
  echo GIT_HEAD_SHORT=%GIT_HEAD_SHORT%
  echo GIT_UPSTREAM=%GIT_UPSTREAM%
  echo GIT_UPSTREAM_HEAD=%GIT_UPSTREAM_HEAD%
  echo GIT_DIRTY_COUNT=%GIT_DIRTY_COUNT%

  echo C_FLOWISE_RUNNING=%C_FLOWISE_RUNNING%
  echo C_FLOWISE_POSTGRES_RUNNING=%C_FLOWISE_POSTGRES_RUNNING%
  echo C_FLOWISE_PROXY_RUNNING=%C_FLOWISE_PROXY_RUNNING%
  echo C_AUTH_SERVICE_RUNNING=%C_AUTH_SERVICE_RUNNING%
  echo C_ACCOUNTING_SERVICE_RUNNING=%C_ACCOUNTING_SERVICE_RUNNING%
  echo C_BRIDGE_RUNNING=%C_BRIDGE_RUNNING%

  echo V_FLOWISE_DATA_PRESENT=%V_FLOWISE_DATA_PRESENT%
  echo V_FLOWISE_POSTGRES_PRESENT=%V_FLOWISE_POSTGRES_PRESENT%

  echo E_FLOWISE_HTTP=%E_FLOWISE_HTTP%
  echo E_PROXY_HTTP=%E_PROXY_HTTP%
  echo E_AUTH_HTTP=%E_AUTH_HTTP%
  echo E_ACCOUNTING_HTTP=%E_ACCOUNTING_HTTP%

  echo FLOWISE_API_KEY_SHA256=%FP_FLOWISE_API_KEY_SHA256%
  echo FLOWISE_SECRETKEY_OVERWRITE_SHA256=%FP_FLOWISE_SECRETKEY_OVERWRITE_SHA256%

  echo PROXY_MONGO_PASSWORD_SHA256=%FP_PROXY_MONGO_PASSWORD_SHA256%
  echo PROXY_JWT_ACCESS_SECRET_SHA256=%FP_PROXY_JWT_ACCESS_SECRET_SHA256%
  echo PROXY_JWT_REFRESH_SECRET_SHA256=%FP_PROXY_JWT_REFRESH_SECRET_SHA256%

  echo AUTH_MONGO_INITDB_ROOT_PASSWORD_SHA256=%FP_AUTH_MONGO_INITDB_ROOT_PASSWORD_SHA256%
  echo AUTH_JWT_ACCESS_SECRET_SHA256=%FP_AUTH_JWT_ACCESS_SECRET_SHA256%
  echo AUTH_JWT_REFRESH_SECRET_SHA256=%FP_AUTH_JWT_REFRESH_SECRET_SHA256%

  echo ACCOUNTING_DB_PASSWORD_SHA256=%FP_ACCOUNTING_DB_PASSWORD_SHA256%
  echo ACCOUNTING_POSTGRES_PASSWORD_SHA256=%FP_ACCOUNTING_POSTGRES_PASSWORD_SHA256%

  echo DATA_AUTH_USERS_COUNT=%DATA_AUTH_USERS_COUNT%
  echo DATA_PROXY_OBJECTS_COUNT=%DATA_PROXY_OBJECTS_COUNT%
  echo DATA_FLOWISE_PG_EST_ROWS=%DATA_FLOWISE_PG_EST_ROWS%
  echo DATA_ACCOUNTING_PG_EST_ROWS=%DATA_ACCOUNTING_PG_EST_ROWS%

  echo IMPACT_ENV_FILES_IN_DIFF=%IMPACT_ENV_FILES_IN_DIFF%
  echo IMPACT_SERVICES_AFFECTED=%IMPACT_SERVICES_AFFECTED%
  echo IMPACT_MAX_CHANGE_TYPE=%IMPACT_MAX_CHANGE_TYPE%
)
if errorlevel 1 (
  call :log ERROR "Failed to write state file"
  exit /b 1
)

call :log OK "State file written: %STATE_FILE%"
exit /b 0

:hash_env_value
setlocal
set "ENV_PATH=%~1"
set "ENV_KEY=%~2"
set "OUTVAR=%~3"
set "HE_PATH=%ENV_PATH%"
set "HE_KEY=%ENV_KEY%"
set "HASH="

for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "$p=$env:HE_PATH; $k=$env:HE_KEY; if(Test-Path $p){ $line = Get-Content $p ^| Where-Object { $_ -match ('^' + [regex]::Escape($k) + '=') } ^| Select-Object -First 1; if($line){ $v = $line.Substring($line.IndexOf('=') + 1); $sha=[System.Security.Cryptography.SHA256]::Create(); $bytes=[System.Text.Encoding]::UTF8.GetBytes($v); (($sha.ComputeHash($bytes) ^| ForEach-Object { $_.ToString('x2') }) -join '') } }"`) do set "HASH=%%H"

endlocal & set "%OUTVAR%=%HASH%"
exit /b 0

:log
set "LEVEL=%~1"
set "MSG=%~2"
echo [%LEVEL%] %MSG%
>> "%LOG_FILE%" echo [%LEVEL%] %MSG%
exit /b 0

:hard_fail
call :log ERROR "Probe failed. Patch must be aborted."
exit /b 1
