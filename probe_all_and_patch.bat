@echo off
REM ============================================================================
REM probe_all_and_patch.bat — Diagnose + auto-fix common LOCAL workstation
REM wiring issues (esp. auth-service MONGO_URI / stale-container drift).
REM
REM Phases:
REM   1. Pre-probe (probe_all.bat)
REM   2. Detect auth-service env drift (container env missing MONGO_URI while
REM      .env has it). If found, force-recreate auth-service container.
REM   3. Wait for auth-service to connect to Mongo.
REM   4. Post-probe (probe_all.bat).
REM   5. Smoke-test admin login.
REM
REM Read-mostly except for the targeted force-recreate. Idempotent.
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
echo [1/5] Pre-probe...
echo [1/5] Pre-probe>> "%LOG%"
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
echo [2/5] Detecting auth-service env drift...
echo [2/5] Detecting auth-service env drift>> "%LOG%"

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
  echo [3/5] Force-recreating auth-service container...
  echo [3/5] Force-recreating auth-service>> "%LOG%"
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
  echo [3/5] No auth-service fix needed; skipping recreate.
  echo [3/5] no fix needed>> "%LOG%"
)

REM ---------------------------------------------------------------------------
echo.
echo [4/5] Post-probe...
echo [4/5] Post-probe>> "%LOG%"
call probe_all.bat >nul 2>&1
for /f "delims=" %%F in ('dir /b /od logs\probe_all-*.txt') do set POST_PROBE=logs\%%F
echo   Post-probe: %POST_PROBE%
echo   Post-probe: %POST_PROBE%>> "%LOG%"

REM ---------------------------------------------------------------------------
echo.
echo [5/5] Smoke-testing admin login...
echo [5/5] Smoke-testing admin login>> "%LOG%"

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
