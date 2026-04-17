@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

REM ============================================================
REM  post-installation-check.bat
REM  ChatProxyPlatform - Post-Installation Health Check
REM
REM  Run this after automated_setup.py to diagnose problems.
REM  Writes a full debug log: post_install_check_TIMESTAMP.log
REM
REM  Usage:
REM    post-installation-check.bat
REM
REM  To push the log for remote debug:
REM    git add post_install_check_*.log
REM    git commit -m "debug: post-install check log"
REM    git push
REM ============================================================

REM ---- Timestamp and log file --------------------------------
for /f "tokens=*" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set TS=%%T
set LOGFILE=%~dp0post_install_check_%TS%.log

REM ---- Bootstrap the log file --------------------------------
>  "%LOGFILE%" echo ChatProxyPlatform Post-Installation Check
>> "%LOGFILE%" echo Timestamp : %TS%
>> "%LOGFILE%" echo Workspace : %~dp0
>> "%LOGFILE%" echo.

goto :MAIN

REM ============================================================
REM  :log  <message>  –  print to console AND append to log
REM ============================================================
:log
  echo %~1
  >> "%LOGFILE%" echo %~1
  goto :eof

REM ============================================================
REM  :section  <title>
REM ============================================================
:section
  echo.
  echo ==================================================================
  echo   %~1
  echo ==================================================================
  >> "%LOGFILE%" echo.
  >> "%LOGFILE%" echo ==================================================================
  >> "%LOGFILE%" echo   %~1
  >> "%LOGFILE%" echo ==================================================================
  goto :eof

REM ============================================================
REM  Temp-file TEE helper
REM  Usage: surround a block with:
REM    set _T=%TEMP%\pic_%RANDOM%.tmp
REM    ( commands ) > "%_T%" 2>&1
REM    type "%_T%"  &  type "%_T%" >> "%LOGFILE%"  &  del "%_T%" 2>nul
REM ============================================================

:MAIN

call :log ""
call :log "======================================================================"
call :log "  ChatProxyPlatform - Post-Installation Check"
call :log "  %TS%"
call :log "======================================================================"
call :log "  Log file: %LOGFILE%"
call :log ""

REM ====================================================================
REM  SECTION 1 - SYSTEM INFO
REM ====================================================================
call :section "1. SYSTEM INFO"

set _T=%TEMP%\pic_%RANDOM%.tmp
(
  echo === Hostname ===
  hostname
  echo.
  echo === Windows version ===
  ver
  echo.
  echo === Docker version ===
  docker version
  echo.
  echo === Docker info ===
  docker info
) > "%_T%" 2>&1
type "%_T%"
type "%_T%" >> "%LOGFILE%"
del "%_T%" 2>nul

REM ====================================================================
REM  SECTION 2 - RUNNING CONTAINERS
REM ====================================================================
call :section "2. DOCKER CONTAINERS"

set _T=%TEMP%\pic_%RANDOM%.tmp
(
  echo === docker ps -a ===
  docker ps -a
  echo.
  echo === docker stats --no-stream ===
  docker stats --no-stream
) > "%_T%" 2>&1
type "%_T%"
type "%_T%" >> "%LOGFILE%"
del "%_T%" 2>nul

REM ====================================================================
REM  SECTION 3 - CONTAINER HEALTH / INSPECT
REM ====================================================================
call :section "3. CONTAINER HEALTH STATUS"

for %%C in (flowise flowise-postgres auth-service mongodb-auth accounting-service postgres-accounting flowise-proxy mongodb-proxy bridge-ui auth-mailhog) do (
  call :log ""
  call :log "  --- %%C ---"
  set _T=%TEMP%\pic_%RANDOM%.tmp
  docker inspect --format "State={{.State.Status}}  Health={{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}  Started={{.State.StartedAt}}" %%C > "!_T!" 2>&1
  type "!_T!"
  type "!_T!" >> "%LOGFILE%"
  del "!_T!" 2>nul
)

REM ====================================================================
REM  SECTION 4 - CONTAINER LOGS (last 100 lines each)
REM ====================================================================
call :section "4. CONTAINER LOGS (last 100 lines each)"

for %%C in (auth-service accounting-service flowise flowise-proxy bridge-ui) do (
  call :log ""
  call :log "  ========== LOG: %%C =========="
  set _T=%TEMP%\pic_%RANDOM%.tmp
  docker logs --tail=100 --timestamps %%C > "!_T!" 2>&1
  type "!_T!"
  type "!_T!" >> "%LOGFILE%"
  del "!_T!" 2>nul
)

REM ====================================================================
REM  SECTION 5 - HTTP HEALTH CHECKS
REM ====================================================================
call :section "5. HTTP HEALTH CHECKS"

powershell -NoProfile -NonInteractive -Command ^
  "$logfile = '%LOGFILE%';" ^
  "$checks = @(" ^
  "  [pscustomobject]@{Name='Auth Service';       Url='http://localhost:3000/health'}," ^
  "  [pscustomobject]@{Name='Accounting Service'; Url='http://localhost:3001/health'}," ^
  "  [pscustomobject]@{Name='Flowise';            Url='http://localhost:3002/api/v1/health'}," ^
  "  [pscustomobject]@{Name='Flowise Proxy';      Url='http://localhost:8000/health'}," ^
  "  [pscustomobject]@{Name='Bridge UI';          Url='http://localhost:3082'}" ^
  ");" ^
  "foreach ($c in $checks) {" ^
  "  try {" ^
  "    $r = Invoke-WebRequest -Uri $c.Url -TimeoutSec 6 -UseBasicParsing -EA Stop;" ^
  "    $line = '  [OK  ] ' + $c.Name + ' (' + $c.Url + ') -> HTTP ' + $r.StatusCode;" ^
  "  } catch {" ^
  "    $line = '  [FAIL] ' + $c.Name + ' (' + $c.Url + ') -> ' + $_.Exception.Message;" ^
  "  }" ^
  "  Write-Host $line; Add-Content -Path $logfile -Value $line" ^
  "}"

REM ====================================================================
REM  SECTION 6 - ADMIN LOGIN TEST  (auth-service direct)
REM ====================================================================
call :section "6. ADMIN LOGIN TEST - Auth Service (port 3000)"

call :log "  Endpoint : POST http://localhost:3000/api/auth/login"
call :log "  Username : admin"
call :log "  Password : admin@admin"
call :log ""

powershell -NoProfile -NonInteractive -Command ^
  "$logfile = '%LOGFILE%';" ^
  "$body = '{\"username\":\"admin\",\"password\":\"admin@admin\"}';" ^
  "try {" ^
  "  $r = Invoke-WebRequest -Method POST -Uri 'http://localhost:3000/api/auth/login'" ^
  "    -Body $body -ContentType 'application/json' -TimeoutSec 10 -UseBasicParsing -EA Stop;" ^
  "  $json = $r.Content | ConvertFrom-Json;" ^
  "  if ($json.accessToken) {" ^
  "    $tok = $json.accessToken;" ^
  "    $preview = $tok.Substring(0, [Math]::Min(40, $tok.Length));" ^
  "    $line = '  [OK  ] Login SUCCESS  accessToken=' + $preview + '...';" ^
  "  } else {" ^
  "    $line = '  [WARN] Responded HTTP ' + $r.StatusCode + ' but NO accessToken.  Body=' + $r.Content;" ^
  "  }" ^
  "} catch {" ^
  "  $line = '  [FAIL] Login FAILED: ' + $_.Exception.Message;" ^
  "  try {" ^
  "    $errBody = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream()).ReadToEnd();" ^
  "    $line += '  ResponseBody=' + $errBody;" ^
  "  } catch {}" ^
  "};" ^
  "Write-Host $line; Add-Content -Path $logfile -Value $line"

REM ====================================================================
REM  SECTION 7 - PROXY AUTHENTICATE TEST  (flowise-proxy port 8000)
REM ====================================================================
call :section "7. PROXY AUTHENTICATE TEST - Flowise Proxy (port 8000)"

call :log "  Endpoint : POST http://localhost:8000/api/v1/chat/authenticate"
call :log "  Username : admin"
call :log "  Password : admin@admin"
call :log ""

powershell -NoProfile -NonInteractive -Command ^
  "$logfile = '%LOGFILE%';" ^
  "$body = '{\"username\":\"admin\",\"password\":\"admin@admin\"}';" ^
  "try {" ^
  "  $r = Invoke-WebRequest -Method POST -Uri 'http://localhost:8000/api/v1/chat/authenticate'" ^
  "    -Body $body -ContentType 'application/json' -TimeoutSec 10 -UseBasicParsing -EA Stop;" ^
  "  $json = $r.Content | ConvertFrom-Json;" ^
  "  if ($json.access_token) {" ^
  "    $tok = $json.access_token;" ^
  "    $preview = $tok.Substring(0, [Math]::Min(40, $tok.Length));" ^
  "    $line = '  [OK  ] Proxy auth SUCCESS  access_token=' + $preview + '...';" ^
  "    Write-Host $line; Add-Content -Path $logfile -Value $line;" ^
  "    try {" ^
  "      $cr = Invoke-WebRequest -Uri 'http://localhost:8000/api/v1/chat/credits'" ^
  "        -Headers @{Authorization='Bearer ' + $tok} -TimeoutSec 6 -UseBasicParsing -EA Stop" ^
  "        | Select-Object -ExpandProperty Content | ConvertFrom-Json;" ^
  "      $cline = '  [INFO] Admin credits: ' + ($cr | ConvertTo-Json -Compress);" ^
  "      Write-Host $cline; Add-Content -Path $logfile -Value $cline" ^
  "    } catch { $x = '  [WARN] Could not fetch credits: ' + $_.Exception.Message; Write-Host $x; Add-Content $logfile $x }" ^
  "  } else {" ^
  "    $line = '  [WARN] Responded HTTP ' + $r.StatusCode + ' but NO access_token.  Body=' + $r.Content;" ^
  "    Write-Host $line; Add-Content -Path $logfile -Value $line" ^
  "  }" ^
  "} catch {" ^
  "  $line = '  [FAIL] Proxy auth FAILED: ' + $_.Exception.Message;" ^
  "  try {" ^
  "    $errBody = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream()).ReadToEnd();" ^
  "    $line += '  ResponseBody=' + $errBody;" ^
  "  } catch {}" ^
  "  Write-Host $line; Add-Content -Path $logfile -Value $line" ^
  "}"

REM ====================================================================
REM  SECTION 8 - MONGODB ADMIN USER INSPECTION
REM ====================================================================
call :section "8. MONGODB: ADMIN USER DOCUMENT"

call :log "  Container: mongodb-auth  DB: auth_db"
call :log ""

set _T=%TEMP%\pic_%RANDOM%.tmp
(
  echo --- admin user document ---
  docker exec mongodb-auth mongosh auth_db --quiet --eval "JSON.stringify(db.users.findOne({username:'admin'}),null,2)"
  echo.
  echo --- all users (username / email / role / isVerified) ---
  docker exec mongodb-auth mongosh auth_db --quiet --eval "db.users.find({},{username:1,email:1,role:1,isVerified:1,_id:0}).forEach(function(d){print(JSON.stringify(d))})"
  echo.
  echo --- user count by role ---
  docker exec mongodb-auth mongosh auth_db --quiet --eval "db.users.aggregate([{$group:{_id:'$role',count:{$sum:1}}}]).forEach(function(d){print(JSON.stringify(d))})"
) > "%_T%" 2>&1
type "%_T%"
type "%_T%" >> "%LOGFILE%"
del "%_T%" 2>nul

REM ====================================================================
REM  SECTION 9 - JWT SECRET CONSISTENCY CHECK
REM ====================================================================
call :section "9. JWT SECRET CONSISTENCY (first 20 chars)"

call :log "  Checking JWT_ACCESS_SECRET across auth-service and flowise-proxy..."
call :log "  (Secrets must match for tokens to validate correctly)"
call :log ""

set _T=%TEMP%\pic_%RANDOM%.tmp
(
  echo --- auth-service JWT_ACCESS_SECRET (first 20 chars) ---
  docker exec auth-service sh -c "echo ${JWT_ACCESS_SECRET:0:20}"
  echo.
  echo --- flowise-proxy JWT_ACCESS_SECRET (first 20 chars) ---
  docker exec flowise-proxy sh -c "echo ${JWT_ACCESS_SECRET:0:20}"
  echo.
  echo --- flowise-proxy JWT_SECRET_KEY (first 20 chars) ---
  docker exec flowise-proxy sh -c "echo ${JWT_SECRET_KEY:0:20}"
) > "%_T%" 2>&1
type "%_T%"
type "%_T%" >> "%LOGFILE%"
del "%_T%" 2>nul

REM ====================================================================
REM  SECTION 10 - AUTO-FIX: FORCE ADMIN isVerified + role IN MONGODB
REM ====================================================================
call :section "10. AUTO-FIX: Force admin isVerified=true and role=admin"

call :log "  This is SAFE to run multiple times."
call :log "  It only updates the admin document in MongoDB."
call :log ""

set _T=%TEMP%\pic_%RANDOM%.tmp
(
  echo --- Updating admin user ---
  docker exec mongodb-auth mongosh auth_db --quiet --eval "var r=db.users.updateOne({username:'admin'},{$set:{isVerified:true,role:'admin'}});print('matched='+r.matchedCount+' modified='+r.modifiedCount);"
  echo.
  echo --- Admin document after fix ---
  docker exec mongodb-auth mongosh auth_db --quiet --eval "JSON.stringify(db.users.findOne({username:'admin'},{username:1,email:1,role:1,isVerified:1,_id:0}),null,2)"
) > "%_T%" 2>&1
type "%_T%"
type "%_T%" >> "%LOGFILE%"
del "%_T%" 2>nul

REM ====================================================================
REM  SECTION 11 - RE-TEST LOGIN AFTER FIX
REM ====================================================================
call :section "11. RE-TEST ADMIN LOGIN AFTER FIX"

call :log ""

powershell -NoProfile -NonInteractive -Command ^
  "$logfile = '%LOGFILE%';" ^
  "$body = '{\"username\":\"admin\",\"password\":\"admin@admin\"}';" ^
  "try {" ^
  "  $r = Invoke-WebRequest -Method POST -Uri 'http://localhost:3000/api/auth/login'" ^
  "    -Body $body -ContentType 'application/json' -TimeoutSec 10 -UseBasicParsing -EA Stop;" ^
  "  $json = $r.Content | ConvertFrom-Json;" ^
  "  if ($json.accessToken) {" ^
  "    $line = '  [OK  ] Login SUCCESS after fix!';" ^
  "  } else {" ^
  "    $line = '  [WARN] HTTP ' + $r.StatusCode + ' but no accessToken.  Body=' + $r.Content;" ^
  "  }" ^
  "} catch {" ^
  "  $line = '  [FAIL] Login STILL FAILED: ' + $_.Exception.Message;" ^
  "  try {" ^
  "    $errBody = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream()).ReadToEnd();" ^
  "    $line += '  ResponseBody=' + $errBody;" ^
  "  } catch {}" ^
  "};" ^
  "Write-Host $line; Add-Content -Path $logfile -Value $line"

REM ====================================================================
REM  SECTION 12 - DOCKER ENVIRONMENT VARIABLES (sensitive preview)
REM ====================================================================
call :section "12. CONTAINER ENVIRONMENT SNAPSHOT (non-secret keys only)"

set _T=%TEMP%\pic_%RANDOM%.tmp
(
  echo --- auth-service env (PORT, NODE_ENV, MONGO_URI pattern) ---
  docker exec auth-service sh -c "env | grep -E '^(PORT|NODE_ENV|MONGO_URI|EMAIL_HOST|API_URL|JWT_ACCESS_EXPIRES)'"
  echo.
  echo --- flowise-proxy env (PORT, NODE_ENV, FLOWISE_API_URL, log level) ---
  docker exec flowise-proxy sh -c "env | grep -E '^(PORT|HOST|NODE_ENV|FLOWISE_API_URL|LOG_LEVEL|DEBUG|EXTERNAL_AUTH_URL|ACCOUNTING_SERVICE_URL)'"
  echo.
  echo --- auth-service /health response ---
  docker exec auth-service sh -c "wget -qO- http://localhost:3000/health 2>&1 || curl -s http://localhost:3000/health 2>&1"
) > "%_T%" 2>&1
type "%_T%"
type "%_T%" >> "%LOGFILE%"
del "%_T%" 2>nul

REM ====================================================================
REM  DONE - SUMMARY
REM ====================================================================
call :section "DONE - SUMMARY"

call :log ""
call :log "  Full debug log written to:"
call :log "  %LOGFILE%"
call :log ""
call :log "  To push this log to the repo for remote debug:"
call :log ""
call :log "    cd /d %~dp0"
call :log "    git add post_install_check_*.log"
call :log "    git commit -m \"debug: post-install check %TS%\""
call :log "    git push"
call :log ""
call :log "  Common admin login failures:"
call :log "    1. isVerified=false in MongoDB  -> Section 10 auto-fix handles this"
call :log "    2. JWT secrets mismatch         -> Check Section 9 output"
call :log "    3. auth-service not ready       -> Check Section 4 logs"
call :log "    4. Wrong password hash          -> Re-run automated_setup.py step 9"
call :log ""

pause
