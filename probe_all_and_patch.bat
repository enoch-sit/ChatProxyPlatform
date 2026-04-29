@echo off
REM ============================================================================
REM probe_all_and_patch.bat — Diagnose + auto-fix common LOCAL workstation
REM wiring issues. Idempotent.
REM
REM Phases:
REM   1. Pre-probe (probe_all.bat)
REM   2. Detect auth-service env drift (container missing MONGO_URI while .env
REM      has it). If found, force-recreate + wait for Mongo connect.
REM   3. Detect flowise-proxy CORS env drift (container CORS_ALLOW_ORIGINS is
REM      empty / "*" / missing http://localhost:3082). If found, rewrite .env
REM      and force-recreate the flowise-proxy container.
REM   4. Probe /api/v1/chatflows/my-chatflows for 500; dump flowise-proxy logs
REM      and CORS preflight headers if it fails.
REM   5. Post-probe + smoke-test admin login.
REM
REM Targeted force-recreates only. Read-mostly otherwise.
REM ============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist logs mkdir logs
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd-HHmmss'"`) do set TS=%%I
set LOG=logs\probe_all_and_patch-%TS%.log

echo ============================================================
echo  probe_all_and_patch  %DATE% %TIME%
echo  Log: %LOG%
echo ============================================================
echo probe_all_and_patch %DATE% %TIME%> "%LOG%"

REM ---------------------------------------------------------------------------
echo.
echo [1/7] Pre-probe...
echo [1/7] Pre-probe>> "%LOG%"
if not exist probe_all.bat (
  echo [FAIL] probe_all.bat not found in current directory.
  echo [FAIL] probe_all.bat not found>> "%LOG%"
  exit /b 1
)
call probe_all.bat >nul 2>&1
for /f "delims=" %%F in ('dir /b /od logs\probe_all-*.txt') do set PRE_PROBE=logs\%%F
echo   Pre-probe: %PRE_PROBE%
echo   Pre-probe: %PRE_PROBE%>> "%LOG%"

REM ---------------------------------------------------------------------------
echo.
echo [2/7] Detecting auth-service env drift...
echo [2/7] Detecting auth-service env drift>> "%LOG%"

set AUTH_FIX_NEEDED=0

REM .env must have MONGO_URI on a line by itself
findstr /B /R "^MONGO_URI=" auth-service\.env >nul 2>&1
if errorlevel 1 (
  echo   [WARN] .env is missing MONGO_URI - appending it.
  echo   [WARN] .env missing MONGO_URI - appending>> "%LOG%"
  powershell -NoProfile -Command "Add-Content -Path auth-service\.env -Value 'MONGO_URI=mongodb://mongodb-auth:27017/auth_db' -Encoding ASCII"
  set AUTH_FIX_NEEDED=1
)

REM Container env must have MONGO_URI
docker exec auth-service printenv MONGO_URI >nul 2>&1
if errorlevel 1 (
  echo   [WARN] auth-service container env missing MONGO_URI - recreate required.
  echo   [WARN] container env missing MONGO_URI>> "%LOG%"
  set AUTH_FIX_NEEDED=1
) else (
  echo   [OK] auth-service container env already has MONGO_URI.
  echo   [OK] container env has MONGO_URI>> "%LOG%"
)

REM ---------------------------------------------------------------------------
if "!AUTH_FIX_NEEDED!"=="1" (
  echo.
  echo [3/7] Force-recreating auth-service container...
  echo [3/7] Force-recreating auth-service>> "%LOG%"
  pushd auth-service
  docker compose -f docker-compose.dev.yml up -d --force-recreate auth-service >> "..\%LOG%" 2>&1
  set RC=!errorlevel!
  popd
  if not "!RC!"=="0" (
    echo [FAIL] docker compose up failed with RC=!RC!
    echo [FAIL] docker compose up RC=!RC!>> "%LOG%"
    exit /b !RC!
  )
  echo   [OK] auth-service recreated.

  echo.
  echo [3b] Waiting up to 60s for auth-service to connect to MongoDB...
  echo [3b] Waiting for MongoDB connection>> "%LOG%"
  set CONNECTED=0
  for /l %%N in (1,1,30) do (
    if "!CONNECTED!"=="0" (
      docker logs auth-service 2>nul | findstr /C:"MongoDB connected successfully" >nul
      if not errorlevel 1 set CONNECTED=1
    )
    if "!CONNECTED!"=="0" powershell -NoProfile -Command "Start-Sleep -Seconds 2" >nul
  )
  if "!CONNECTED!"=="1" (
    echo   [OK] MongoDB connected.
    echo   [OK] MongoDB connected>> "%LOG%"
  ) else (
    echo   [WARN] Did not see "MongoDB connected successfully" within 60s.
    echo   [WARN] no Mongo connect msg in 60s>> "%LOG%"
    echo   Last 30 lines of auth-service logs:
    docker logs auth-service --tail 30
  )
) else (
  echo.
  echo [3/7] No auth-service fix needed; skipping recreate.
  echo [3/7] no fix needed>> "%LOG%"
)

REM ---------------------------------------------------------------------------
echo.
echo [4/7] Detecting flowise-proxy CORS env drift...
echo [4/7] Detecting flowise-proxy CORS env drift>> "%LOG%"

set PROXY_FIX_NEEDED=0
set EXPECTED_CORS=http://localhost:3082,http://localhost:3000,http://localhost:3001,http://localhost:3002,http://localhost:8000

REM .env must declare CORS_ALLOW_ORIGINS containing localhost:3082 (not "*")
set ENV_CORS_OK=0
findstr /B /R "^CORS_ALLOW_ORIGINS=" flowise-proxy-service-py\.env >nul 2>&1
if not errorlevel 1 (
  findstr /R "^CORS_ALLOW_ORIGINS=.*localhost:3082" flowise-proxy-service-py\.env >nul 2>&1
  if not errorlevel 1 set ENV_CORS_OK=1
)
if "!ENV_CORS_OK!"=="0" (
  echo   [WARN] flowise-proxy .env missing/invalid CORS_ALLOW_ORIGINS - rewriting.
  echo   [WARN] proxy .env CORS missing/invalid - rewriting>> "%LOG%"
  powershell -NoProfile -Command "$f='flowise-proxy-service-py\.env'; if (Test-Path $f) { $c = Get-Content $f | Where-Object { $_ -notmatch '^CORS_ALLOW_ORIGINS=' }; $c += 'CORS_ALLOW_ORIGINS=%EXPECTED_CORS%'; Set-Content -Path $f -Value $c -Encoding ASCII } else { Write-Host '[FAIL] proxy .env not found'; exit 1 }"
  set PROXY_FIX_NEEDED=1
)

REM Container env must have CORS_ALLOW_ORIGINS containing localhost:3082
set CONTAINER_CORS=
for /f "usebackq delims=" %%V in (`docker exec flowise-proxy printenv CORS_ALLOW_ORIGINS 2^>nul`) do set CONTAINER_CORS=%%V
echo   container CORS_ALLOW_ORIGINS=!CONTAINER_CORS!>> "%LOG%"
echo "!CONTAINER_CORS!" | findstr /C:"localhost:3082" >nul
if errorlevel 1 (
  echo   [WARN] flowise-proxy container env CORS_ALLOW_ORIGINS missing localhost:3082.
  echo   [WARN] proxy container CORS missing 3082>> "%LOG%"
  set PROXY_FIX_NEEDED=1
) else (
  echo   [OK] flowise-proxy container env CORS_ALLOW_ORIGINS already correct.
  echo   [OK] proxy container CORS ok>> "%LOG%"
)

REM ---------------------------------------------------------------------------
if "!PROXY_FIX_NEEDED!"=="1" (
  echo.
  echo [5/7] Force-recreating flowise-proxy container...
  echo [5/7] Force-recreating flowise-proxy>> "%LOG%"
  pushd flowise-proxy-service-py
  if exist docker-compose.linux.yml (
    docker compose -f docker-compose.linux.yml up -d --force-recreate flowise-proxy >> "..\%LOG%" 2>&1
  ) else (
    docker compose up -d --force-recreate flowise-proxy >> "..\%LOG%" 2>&1
  )
  set RC=!errorlevel!
  popd
  if not "!RC!"=="0" (
    echo   [WARN] docker compose up failed for flowise-proxy with RC=!RC!
    echo   [WARN] proxy compose up RC=!RC!>> "%LOG%"
  ) else (
    echo   [OK] flowise-proxy recreated.
  )

  echo.
  echo [5b] Waiting up to 60s for flowise-proxy /docs to respond...
  set PROXY_UP=0
  for /l %%N in (1,1,30) do (
    if "!PROXY_UP!"=="0" (
      curl -s -o nul -w "%%{http_code}" --max-time 2 http://localhost:8000/docs > "%TEMP%\px.txt" 2>nul
      set /p PROXY_CODE=<"%TEMP%\px.txt"
      if "!PROXY_CODE!"=="200" set PROXY_UP=1
    )
    if "!PROXY_UP!"=="0" powershell -NoProfile -Command "Start-Sleep -Seconds 2" >nul
  )
  if "!PROXY_UP!"=="1" (
    echo   [OK] flowise-proxy is up.
    echo   [OK] flowise-proxy up>> "%LOG%"
  ) else (
    echo   [WARN] flowise-proxy /docs not 200 within 60s.
    echo   [WARN] flowise-proxy not up>> "%LOG%"
    echo   Last 30 lines of flowise-proxy logs:
    docker logs flowise-proxy --tail 30
  )
) else (
  echo.
  echo [5/7] No flowise-proxy fix needed; skipping recreate.
  echo [5/7] no proxy fix needed>> "%LOG%"
)

REM ---------------------------------------------------------------------------
echo.
echo [6/7] CORS preflight + chatflows probe...
echo [6/7] CORS preflight + chatflows probe>> "%LOG%"

echo   --- OPTIONS /api/v1/chatflows/my-chatflows (preflight) ---
echo   --- OPTIONS preflight ---            >> "%LOG%"
curl -s -i -o "%TEMP%\preflight.txt" --max-time 5 ^
  -X OPTIONS http://localhost:8000/api/v1/chatflows/my-chatflows ^
  -H "Origin: http://localhost:3082" ^
  -H "Access-Control-Request-Method: GET" ^
  -H "Access-Control-Request-Headers: authorization,content-type" 2>nul
findstr /I "HTTP/ access-control-allow-origin access-control-allow-credentials" "%TEMP%\preflight.txt"
findstr /I "HTTP/ access-control-allow-origin access-control-allow-credentials" "%TEMP%\preflight.txt" >> "%LOG%"

echo.
echo   --- GET /api/v1/chatflows/my-chatflows (no auth, expect 401, NOT 500) ---
echo   --- GET my-chatflows ---             >> "%LOG%"
curl -s -o nul -w "  status=%%{http_code}\n" --max-time 5 http://localhost:8000/api/v1/chatflows/my-chatflows
curl -s -o nul -w "  status=%%{http_code}" --max-time 5 http://localhost:8000/api/v1/chatflows/my-chatflows >> "%LOG%" 2>&1
echo.>> "%LOG%"

echo   --- last 40 lines of flowise-proxy logs ---
echo   --- flowise-proxy logs ---            >> "%LOG%"
docker logs flowise-proxy --tail 40 2>&1
docker logs flowise-proxy --tail 40 >> "%LOG%" 2>&1

REM ---------------------------------------------------------------------------
echo.
echo [7/7] Post-probe...
echo [7/7] Post-probe>> "%LOG%"
call probe_all.bat >nul 2>&1
for /f "delims=" %%F in ('dir /b /od logs\probe_all-*.txt') do set POST_PROBE=logs\%%F
echo   Post-probe: %POST_PROBE%
echo   Post-probe: %POST_PROBE%>> "%LOG%"

REM ---------------------------------------------------------------------------
echo.
echo [7b] Smoke-testing admin login...
echo [7b] Smoke-testing admin login>> "%LOG%"

set ADMIN_USERNAME_VAL=admin
if defined ADMIN_USERNAME set ADMIN_USERNAME_VAL=%ADMIN_USERNAME%
set ADMIN_PASSWORD_VAL=admin@admin
if defined ADMIN_PASSWORD set ADMIN_PASSWORD_VAL=%ADMIN_PASSWORD%

curl -s -o nul -w "  /health -> HTTP %%{http_code}\n" --max-time 5 http://localhost:3000/health
curl -s -o nul -w "  POST /api/auth/login -> HTTP %%{http_code}\n" --max-time 5 ^
  -X POST -H "Content-Type: application/json" ^
  -d "{\"username\":\"%ADMIN_USERNAME_VAL%\",\"password\":\"%ADMIN_PASSWORD_VAL%\"}" ^
  http://localhost:3000/api/auth/login

echo.
echo ============================================================
echo  Summary
echo ============================================================
echo   Pre-probe : %PRE_PROBE%
echo   Post-probe: %POST_PROBE%
echo   Patch log : %LOG%
echo.
echo Compare pre/post probe files to confirm fix.
echo If admin login returned HTTP 200, run:
echo   powershell -ExecutionPolicy Bypass -File scripts\backfill-accounting-users.ps1
echo.

endlocal
exit /b 0
