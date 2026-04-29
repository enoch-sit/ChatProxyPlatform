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
REM   4. Detect flowise-proxy Mongo auth drift. If logs show Authentication
REM      failed, reset the proxy Mongo volume and recreate mongodb-proxy plus
REM      flowise-proxy so root credentials reinitialize from compose.
REM   5. Probe /api/v1/chatflows/my-chatflows for 500; dump flowise-proxy logs
REM      and CORS preflight headers if it fails.
REM   6. Post-probe + smoke-test admin login.
REM
REM Targeted force-recreates only. Read-mostly otherwise.
REM ============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"
set ROOT_DIR=%CD%

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
echo [1/8] Pre-probe...
echo [1/8] Pre-probe>> "%LOG%"
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
echo [2/8] Detecting auth-service env drift...
echo [2/8] Detecting auth-service env drift>> "%LOG%"

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
  echo [3/8] Force-recreating auth-service container...
  echo [3/8] Force-recreating auth-service>> "%LOG%"
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
  echo [3b] Waiting up to 10s for auth-service to connect to MongoDB...
  echo [3b] Waiting for MongoDB connection>> "%LOG%"
  set CONNECTED=0
  for /l %%N in (1,1,10) do (
    if "!CONNECTED!"=="0" (
      docker logs auth-service 2>nul | findstr /C:"MongoDB connected successfully" >nul
      if not errorlevel 1 set CONNECTED=1
    )
    if "!CONNECTED!"=="0" powershell -NoProfile -Command "Start-Sleep -Seconds 1" >nul
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
  echo [3/8] No auth-service fix needed; skipping recreate.
  echo [3/8] no fix needed>> "%LOG%"
)

REM ---------------------------------------------------------------------------
echo.
echo [4/8] Detecting flowise-proxy CORS env drift...
echo [4/8] Detecting flowise-proxy CORS env drift>> "%LOG%"

set PROXY_FIX_NEEDED=0
set PROXY_MONGO_ENV_REPAIRED=0
set PROXY_FLOWISE_KEY_REPAIRED=0
set EXPECTED_CORS=http://localhost:3082,http://localhost:3000,http://localhost:3001,http://localhost:3002,http://localhost:8000

REM flowise-proxy .env must also expose MONGO_PASSWORD for mongodb-proxy compose env.
set PROXY_MONGO_ENV_OK=0
findstr /B /R "^MONGO_PASSWORD=" flowise-proxy-service-py\.env >nul 2>&1
if not errorlevel 1 set PROXY_MONGO_ENV_OK=1
if "!PROXY_MONGO_ENV_OK!"=="0" (
  echo   [WARN] flowise-proxy .env missing MONGO_PASSWORD - deriving it from MONGODB_URL.
  echo   [WARN] proxy .env missing MONGO_PASSWORD - deriving from MONGODB_URL>> "%LOG%"
  powershell -NoProfile -Command "$f='flowise-proxy-service-py\.env'; $mongoUrl = (Get-Content $f | Where-Object { $_ -match '^MONGODB_URL=' } | Select-Object -First 1); if (-not $mongoUrl) { Write-Error 'MONGODB_URL missing from flowise-proxy-service-py\.env'; exit 1 }; $password = ([uri]$mongoUrl.Substring($mongoUrl.IndexOf('=') + 1)).UserInfo.Split(':',2)[1]; if (-not $password) { Write-Error 'Could not extract Mongo password from MONGODB_URL'; exit 1 }; $content = Get-Content $f; $content += ('MONGO_PASSWORD=' + $password); Set-Content -Path $f -Value $content -Encoding ASCII"
  if errorlevel 1 (
    echo   [WARN] failed to derive MONGO_PASSWORD from MONGODB_URL.
    echo   [WARN] failed deriving proxy MONGO_PASSWORD from MONGODB_URL>> "%LOG%"
  ) else (
    echo   [OK] flowise-proxy .env MONGO_PASSWORD restored from MONGODB_URL.
    echo   [OK] proxy .env MONGO_PASSWORD restored from MONGODB_URL>> "%LOG%"
    set PROXY_MONGO_ENV_REPAIRED=1
  )
)

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
  echo [5/8] Force-recreating flowise-proxy container...
  echo [5/8] Force-recreating flowise-proxy>> "%LOG%"
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
  echo [5b] Waiting up to 10s for flowise-proxy /docs to respond...
  set PROXY_UP=0
  for /l %%N in (1,1,10) do (
    if "!PROXY_UP!"=="0" (
      curl -s -o nul -w "%%{http_code}" --max-time 2 http://localhost:8000/docs > "%TEMP%\px.txt" 2>nul
      set /p PROXY_CODE=<"%TEMP%\px.txt"
      if "!PROXY_CODE!"=="200" set PROXY_UP=1
    )
    if "!PROXY_UP!"=="0" powershell -NoProfile -Command "Start-Sleep -Seconds 1" >nul
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
  echo [5/8] No flowise-proxy fix needed; skipping recreate.
  echo [5/8] no proxy fix needed>> "%LOG%"
)

REM ---------------------------------------------------------------------------
echo.
echo [6/8] Detecting flowise-proxy Mongo auth drift...
echo [6/8] Detecting flowise-proxy Mongo auth drift>> "%LOG%"

set PROXY_MONGO_RESET_NEEDED=0
if "!PROXY_MONGO_ENV_REPAIRED!"=="1" (
  echo   [WARN] flowise-proxy Mongo env was repaired - forcing mongodb-proxy reset.
  echo   [WARN] proxy Mongo env repaired - forcing reset>> "%LOG%"
  set PROXY_MONGO_RESET_NEEDED=1
)

docker logs flowise-proxy 2>&1 | findstr /C:"pymongo.errors.OperationFailure: Authentication failed." >nul
if errorlevel 1 (
  echo   [OK] flowise-proxy logs do not show Mongo auth failure.
  echo   [OK] no proxy Mongo auth failure signature>> "%LOG%"
) else (
  echo   [WARN] flowise-proxy logs show Mongo auth failure.
  echo   [WARN] proxy Mongo auth failure signature detected>> "%LOG%"
  set PROXY_MONGO_RESET_NEEDED=1
)

docker logs flowise-proxy 2>&1 | findstr /C:"No address associated with hostname" >nul
if errorlevel 1 (
  echo   [OK] flowise-proxy logs do not show Mongo hostname resolution failure.
  echo   [OK] no proxy Mongo hostname resolution failure>> "%LOG%"
) else (
  echo   [WARN] flowise-proxy logs show Mongo hostname resolution failure.
  echo   [WARN] proxy Mongo hostname resolution failure detected>> "%LOG%"
  set PROXY_MONGO_RESET_NEEDED=1
)

docker logs mongodb-proxy 2>&1 | findstr /C:"missing 'MONGO_INITDB_ROOT_USERNAME' or 'MONGO_INITDB_ROOT_PASSWORD'" >nul
if errorlevel 1 (
  echo   [OK] mongodb-proxy logs do not show missing root env.
  echo   [OK] no mongodb-proxy missing root env signature>> "%LOG%"
) else (
  echo   [WARN] mongodb-proxy logs show missing root env.
  echo   [WARN] mongodb-proxy missing root env signature detected>> "%LOG%"
  set PROXY_MONGO_RESET_NEEDED=1
)

if "!PROXY_MONGO_RESET_NEEDED!"=="1" (
  echo.
  echo [6b] Resetting flowise-proxy Mongo volume and recreating proxy stack...
  echo [6b] Resetting proxy Mongo volume + stack>> "%LOG%"
  pushd flowise-proxy-service-py
  docker compose down -v >> "%ROOT_DIR%\%LOG%" 2>&1
  set RC=!errorlevel!
  if not "!RC!"=="0" (
    popd
    echo   [WARN] docker compose down -v failed with RC=!RC!
    echo   [WARN] proxy compose down -v RC=!RC!>> "%LOG%"
  ) else (
    docker compose up -d mongodb >> "%ROOT_DIR%\%LOG%" 2>&1
    set RC=!errorlevel!
    if not "!RC!"=="0" (
      popd
      echo   [WARN] docker compose up failed after proxy Mongo reset with RC=!RC!
      echo   [WARN] proxy compose up after reset RC=!RC!>> "%LOG%"
    ) else (
      echo   [OK] mongodb-proxy recreated; waiting for health before starting flowise-proxy.
      echo   [OK] mongodb-proxy recreated after volume reset>> "%LOG%"

      echo.
      echo [6c] Waiting up to 10s for mongodb-proxy health...
      set PROXY_MONGO_HEALTHY=0
      for /l %%N in (1,1,10) do (
        if "!PROXY_MONGO_HEALTHY!"=="0" (
          for /f "usebackq delims=" %%H in (`docker inspect mongodb-proxy --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}" 2^>nul`) do set PROXY_MONGO_STATUS=%%H
          if /I "!PROXY_MONGO_STATUS!"=="healthy" set PROXY_MONGO_HEALTHY=1
        )
        if "!PROXY_MONGO_HEALTHY!"=="0" powershell -NoProfile -Command "Start-Sleep -Seconds 1" >nul
      )
      if "!PROXY_MONGO_HEALTHY!"=="1" (
        echo   [OK] mongodb-proxy is healthy.
        echo   [OK] mongodb-proxy healthy after reset>> "%LOG%"
      ) else (
        echo   [WARN] mongodb-proxy did not report healthy within 10s.
        echo   [WARN] mongodb-proxy not healthy within 10s>> "%LOG%"
      )

      docker compose up -d flowise-proxy >> "%ROOT_DIR%\%LOG%" 2>&1
      set RC=!errorlevel!
      popd
      if not "!RC!"=="0" (
        echo   [WARN] docker compose up failed when starting flowise-proxy after Mongo reset with RC=!RC!
        echo   [WARN] flowise-proxy compose up after Mongo reset RC=!RC!>> "%LOG%"
      ) else (
        echo   [OK] flowise-proxy Mongo volume reset and stack recreated.
        echo   [OK] proxy Mongo reset + recreate complete>> "%LOG%"

        echo.
        echo [6d] Waiting up to 10s for flowise-proxy /docs after Mongo reset...
        set PROXY_UP=0
        for /l %%N in (1,1,10) do (
          if "!PROXY_UP!"=="0" (
            curl -s -o nul -w "%%{http_code}" --max-time 2 http://localhost:8000/docs > "%TEMP%\px.txt" 2>nul
            set /p PROXY_CODE=<"%TEMP%\px.txt"
            if "!PROXY_CODE!"=="200" set PROXY_UP=1
          )
          if "!PROXY_UP!"=="0" powershell -NoProfile -Command "Start-Sleep -Seconds 1" >nul
        )
        if "!PROXY_UP!"=="1" (
          echo   [OK] flowise-proxy is up after Mongo reset.
          echo   [OK] flowise-proxy up after Mongo reset>> "%LOG%"
        ) else (
          echo   [WARN] flowise-proxy /docs not 200 within 10s after Mongo reset.
          echo   [WARN] flowise-proxy not up after Mongo reset>> "%LOG%"
        )
      )
    )
  )
)

REM flowise-proxy .env should not keep the placeholder Flowise API key.
set PROXY_FLOWISE_KEY=
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /B /R "^FLOWISE_API_KEY=" flowise-proxy-service-py\.env 2^>nul`) do set PROXY_FLOWISE_KEY=%%B
if /I "!PROXY_FLOWISE_KEY!"=="your_flowise_api_key_here" (
  echo   [WARN] flowise-proxy .env still has placeholder FLOWISE_API_KEY.
  echo   [WARN] proxy .env has placeholder FLOWISE_API_KEY>> "%LOG%"
  if defined FLOWISE_API_KEY_REPAIR (
    echo   [INFO] replacing placeholder FLOWISE_API_KEY from FLOWISE_API_KEY_REPAIR.
    echo   [INFO] replacing placeholder FLOWISE_API_KEY from FLOWISE_API_KEY_REPAIR>> "%LOG%"
    powershell -NoProfile -Command "$f='flowise-proxy-service-py\.env'; $replacement='FLOWISE_API_KEY=%FLOWISE_API_KEY_REPAIR%'; $content = Get-Content $f | ForEach-Object { if ($_ -match '^FLOWISE_API_KEY=') { $replacement } else { $_ } }; Set-Content -Path $f -Value $content -Encoding ASCII"
    if errorlevel 1 (
      echo   [WARN] failed to replace placeholder FLOWISE_API_KEY from FLOWISE_API_KEY_REPAIR.
      echo   [WARN] failed replacing placeholder FLOWISE_API_KEY>> "%LOG%"
    ) else (
      echo   [OK] flowise-proxy .env FLOWISE_API_KEY updated from FLOWISE_API_KEY_REPAIR.
      echo   [OK] proxy .env FLOWISE_API_KEY updated from FLOWISE_API_KEY_REPAIR>> "%LOG%"
      set PROXY_FIX_NEEDED=1
      set PROXY_FLOWISE_KEY_REPAIRED=1
    )
  ) else (
    echo   [WARN] set FLOWISE_API_KEY_REPAIR to auto-repair the proxy Flowise API key in this run.
    echo   [WARN] FLOWISE_API_KEY_REPAIR not set for placeholder Flowise API key>> "%LOG%"
  )
)

REM Validate the upstream Flowise key after the proxy stack is healthy enough to answer requests.
echo.
echo [6e] Validating upstream Flowise API key from flowise-proxy .env...
echo [6e] Validating upstream Flowise API key>> "%LOG%"
set FLOWISE_KEY_STATUS=unknown
set FLOWISE_KEY_HTTP=
set FLOWISE_PROXY_KEY=
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /B /R "^FLOWISE_API_KEY=" flowise-proxy-service-py\.env 2^>nul`) do set FLOWISE_PROXY_KEY=%%B
if not defined FLOWISE_PROXY_KEY (
  echo   [WARN] flowise-proxy .env has no FLOWISE_API_KEY entry.
  echo   [WARN] proxy .env missing FLOWISE_API_KEY>> "%LOG%"
  set FLOWISE_KEY_STATUS=missing
) else if "!FLOWISE_PROXY_KEY!"=="" (
  echo   [WARN] flowise-proxy .env FLOWISE_API_KEY is empty.
  echo   [WARN] proxy .env FLOWISE_API_KEY empty>> "%LOG%"
  set FLOWISE_KEY_STATUS=missing
) else (
  curl -s -o nul -w "%%{http_code}" --max-time 10 -H "Authorization: Bearer !FLOWISE_PROXY_KEY!" http://localhost:3002/api/v1/chatflows > "%TEMP%\flowise-key-http.txt" 2>nul
  set /p FLOWISE_KEY_HTTP=<"%TEMP%\flowise-key-http.txt"
  if "!FLOWISE_KEY_HTTP!"=="200" (
    echo   [OK] upstream Flowise API key is valid.
    echo   [OK] upstream Flowise API key valid>> "%LOG%"
    set FLOWISE_KEY_STATUS=valid
  ) else (
    echo   [WARN] upstream Flowise API key validation failed with HTTP !FLOWISE_KEY_HTTP!.
    echo   [WARN] upstream Flowise API key invalid HTTP !FLOWISE_KEY_HTTP!>> "%LOG%"
    set FLOWISE_KEY_STATUS=invalid
    if defined FLOWISE_API_KEY_REPAIR if not "!PROXY_FLOWISE_KEY_REPAIRED!"=="1" (
      echo   [INFO] updating FLOWISE_API_KEY from FLOWISE_API_KEY_REPAIR and recreating flowise-proxy.
      echo   [INFO] updating FLOWISE_API_KEY from FLOWISE_API_KEY_REPAIR>> "%LOG%"
      powershell -NoProfile -Command "$f='flowise-proxy-service-py\.env'; $replacement='FLOWISE_API_KEY=%FLOWISE_API_KEY_REPAIR%'; $content = Get-Content $f | ForEach-Object { if ($_ -match '^FLOWISE_API_KEY=') { $replacement } else { $_ } }; Set-Content -Path $f -Value $content -Encoding ASCII"
      if errorlevel 1 (
        echo   [WARN] failed to update invalid FLOWISE_API_KEY from FLOWISE_API_KEY_REPAIR.
        echo   [WARN] failed updating invalid FLOWISE_API_KEY>> "%LOG%"
      ) else (
        set PROXY_FIX_NEEDED=1
        set PROXY_FLOWISE_KEY_REPAIRED=1
        pushd flowise-proxy-service-py
        docker compose up -d --force-recreate flowise-proxy >> "%ROOT_DIR%\%LOG%" 2>&1
        set RC=!errorlevel!
        popd
        if not "!RC!"=="0" (
          echo   [WARN] flowise-proxy recreate failed after FLOWISE_API_KEY repair with RC=!RC!.
          echo   [WARN] flowise-proxy recreate failed after FLOWISE_API_KEY repair RC=!RC!>> "%LOG%"
        ) else (
          echo   [OK] flowise-proxy recreated after FLOWISE_API_KEY repair.
          echo   [OK] flowise-proxy recreated after FLOWISE_API_KEY repair>> "%LOG%"
        )
      )
    )
  )
)

REM ---------------------------------------------------------------------------
echo.
echo [7/8] CORS preflight + chatflows probe...
echo [7/8] CORS preflight + chatflows probe>> "%LOG%"

set ADMIN_USERNAME_VAL=admin
if defined ADMIN_USERNAME set ADMIN_USERNAME_VAL=%ADMIN_USERNAME%
set ADMIN_PASSWORD_VAL=admin@admin
if defined ADMIN_PASSWORD set ADMIN_PASSWORD_VAL=%ADMIN_PASSWORD%
set FLOWISE_API_KEY_PROBE_VAL=
if defined FLOWISE_API_KEY_PROBE set FLOWISE_API_KEY_PROBE_VAL=%FLOWISE_API_KEY_PROBE%

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
echo   --- GET /api/v1/chatflows/my-chatflows (no auth, expect 401/403, NOT 500) ---
echo   --- GET my-chatflows unauth ---      >> "%LOG%"
curl -s -o nul -w "  status=%%{http_code}\n" --max-time 5 http://localhost:8000/api/v1/chatflows/my-chatflows
curl -s -o nul -w "  status=%%{http_code}" --max-time 5 http://localhost:8000/api/v1/chatflows/my-chatflows >> "%LOG%" 2>&1
echo.>> "%LOG%"

echo.
echo   --- POST /api/v1/chat/authenticate (bridge login path) ---
echo   --- POST bridge authenticate ---     >> "%LOG%"
if defined FLOWISE_API_KEY_PROBE_VAL (
  echo   [INFO] probing admin Flowise API key save/test path with FLOWISE_API_KEY_PROBE.
  echo   [INFO] probing admin Flowise API key save/test path>> "%LOG%"
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\probe_flowise_proxy_endpoints.ps1" -Username "%ADMIN_USERNAME_VAL%" -Password "%ADMIN_PASSWORD_VAL%" -FlowiseApiKey "%FLOWISE_API_KEY_PROBE_VAL%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\probe_flowise_proxy_endpoints.ps1" -Username "%ADMIN_USERNAME_VAL%" -Password "%ADMIN_PASSWORD_VAL%"
)

echo.
echo   --- last 120 lines of flowise-proxy logs ---
echo   --- flowise-proxy logs ---            >> "%LOG%"
docker logs flowise-proxy --tail 120 2>&1
docker logs flowise-proxy --tail 120 >> "%LOG%" 2>&1

echo.
echo   --- last 80 lines of mongodb-proxy logs ---
echo   --- mongodb-proxy logs ---            >> "%LOG%"
docker logs mongodb-proxy --tail 80 2>&1
docker logs mongodb-proxy --tail 80 >> "%LOG%" 2>&1

REM ---------------------------------------------------------------------------
echo.
echo [8/8] Post-probe...
echo [8/8] Post-probe>> "%LOG%"
call probe_all.bat >nul 2>&1
for /f "delims=" %%F in ('dir /b /od logs\probe_all-*.txt') do set POST_PROBE=logs\%%F
echo   Post-probe: %POST_PROBE%
echo   Post-probe: %POST_PROBE%>> "%LOG%"

REM ---------------------------------------------------------------------------
echo.
echo [8b] Smoke-testing admin login...
echo [8b] Smoke-testing admin login>> "%LOG%"

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
