@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Fix broken git branch state, collect machine state, then run comprehensive workstation probe.
REM Exit code: 0 = probe passed, 1 = abort.
REM Usage: probe_and_fix.bat

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo ============================================================
echo  ChatProxy Workstation -- Git Fix + Machine State + Probe
echo ============================================================
echo.

REM ── [MACHINE IDENTITY] ───────────────────────────────────────
echo [MACHINE IDENTITY]
echo   Computer : %COMPUTERNAME%
echo   User     : %USERNAME%
for /f "tokens=* delims=" %%V in ('ver') do echo   OS       : %%V
echo.

REM ── [DISK SPACE] ─────────────────────────────────────────────
echo [DISK SPACE  C:\]
powershell -NoProfile -Command "Get-PSDrive C | ForEach-Object { $free=[math]::Round($_.Free/1GB,1); $used=[math]::Round($_.Used/1GB,1); $total=$free+$used; Write-Host ('  Used: {0} GB    Free: {1} GB    Total: {2} GB' -f $used, $free, $total) }"
echo.

REM ── [NETWORK] ────────────────────────────────────────────────
echo [NETWORK]
powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.254\.' } | ForEach-Object { Write-Host ('  {0,-35} {1}' -f $_.InterfaceAlias, $_.IPAddress) }"
echo.
echo   WireGuard hub (10.10.0.1):
ping -n 1 -w 1000 10.10.0.1 >nul 2>&1
if errorlevel 1 (
  echo   [WARN] WireGuard hub 10.10.0.1 unreachable -- VPN may be down
) else (
  echo   [OK]   WireGuard hub 10.10.0.1 reachable
)
echo.

REM ── [GIT] Step 1: Verify git is available ───────────────────
echo [GIT]
echo [INFO] Checking git...
git --version >nul 2>&1
if errorlevel 1 (
  echo [FAIL] git not found in PATH. Aborting.
  exit /b 1
)

REM ── Step 2: Fetch and prune stale remote refs ────────────────
echo [INFO] Fetching origin and pruning stale remote refs...
git -C "%ROOT%" fetch origin --prune
if errorlevel 1 (
  echo [FAIL] git fetch failed. Check network / credentials.
  exit /b 1
)
echo [OK] Fetch complete.

REM ── Step 2b: Show pending remote commits ─────────────────────
set "PENDING_COUNT=0"
for /f %%N in ('git -C "%ROOT%" rev-list --count HEAD..origin/bhss 2^>nul') do set "PENDING_COUNT=%%N"
if "%PENDING_COUNT%"=="0" (
  echo [OK] No pending commits on origin/bhss.
) else (
  echo [INFO] %PENDING_COUNT% commits available on origin/bhss:
  git -C "%ROOT%" log --oneline HEAD..origin/bhss
)
echo.

REM ── [PATCH IMPACT ANALYSIS] ─────────────────────────────────
set "IMPACT_ENV_FILES_IN_DIFF=N/A"
set "IMPACT_SERVICES_AFFECTED=N/A"
set "IMPACT_MAX_CHANGE_TYPE=N/A"

if "%PENDING_COUNT%"=="0" goto :impact_done

echo [PATCH IMPACT ANALYSIS]  %PENDING_COUNT% commits incoming
set "IA_TMP=%TEMP%\probe_impact_%RANDOM%.txt"
del "%IA_TMP%" 2>nul

powershell -NoProfile -Command "$root=$env:ROOT; $tmp=$env:IA_TMP; $changed=@(git -C $root diff --name-only HEAD..origin/bhss 2>$null); $buckets=@{}; foreach ($svc in @('auth-service','accounting-service','flowise-proxy-service-py','flowise','bridge','root')) { $buckets[$svc]=@{f=0;mx=''} }; $ord=@{'IMAGE REBUILD'=3;'SOURCE -- rebuild likely'=2;'CONFIG/SCRIPTS'=1;''=0}; function gimpact { param([string]$x); if ($x -match 'Dockerfile|requirements\.txt|package\.json|package-lock\.json') { return 'IMAGE REBUILD' }; if ($x -match '\.ts$|\.tsx$|\.py$|\.js$') { return 'SOURCE -- rebuild likely' }; 'CONFIG/SCRIPTS' }; $envHit='NONE'; $aff=@(); foreach ($f in $changed) { if ($f -match '\.env') { $envHit=$f }; $bk='root'; foreach ($s in @('auth-service','accounting-service','flowise-proxy-service-py','flowise','bridge')) { if ($f -like ($s+'/*')) { $bk=$s; break } }; $imp=gimpact $f; $buckets[$bk].f++; if ($ord[$imp] -gt $ord[$buckets[$bk].mx]) { $buckets[$bk].mx=$imp } }; Write-Host ('  {0,-30} {1,-5} {2}' -f 'Service','Files','Max Impact'); Write-Host ('  '+('-'*60)); $omx=''; foreach ($s in @('auth-service','accounting-service','flowise-proxy-service-py','flowise','bridge','root')) { $b=$buckets[$s]; if ($b.f -gt 0) { $aff+=$s; Write-Host ('  {0,-30} {1,-5} {2}' -f $s,$b.f,$b.mx); if ($ord[$b.mx] -gt $ord[$omx]) { $omx=$b.mx } } }; if ($envHit -ne 'NONE') { Write-Host ('  [WARN] .env file in diff: '+$envHit+' -- VERIFY intentional!') -ForegroundColor Yellow } else { Write-Host ('  {0,-30} {1}' -f '.env files in diff:','NONE (safe)') }; $affStr=if ($aff.Count -gt 0) { $aff -join ',' } else { 'none' }; @('IMPACT_ENV_FILES_IN_DIFF='+$envHit,'IMPACT_SERVICES_AFFECTED='+$affStr,'IMPACT_MAX_CHANGE_TYPE='+$omx) | Set-Content $tmp"

if not exist "%IA_TMP%" goto :impact_done
for /f "usebackq tokens=1,* delims==" %%K in ("%IA_TMP%") do set "%%K=%%L"
del "%IA_TMP%" 2>nul

:impact_done
echo.

REM ── Step 3: Switch to bhss ────────────────────────────────────
echo [INFO] Switching to bhss branch...
for /f "usebackq delims=" %%B in (`git -C "%ROOT%" rev-parse --abbrev-ref HEAD 2^>nul`) do set "CURRENT_BRANCH=%%B"

if /i "%CURRENT_BRANCH%"=="bhss" (
  echo [OK] Already on bhss.
) else (
  echo [INFO] Currently on "%CURRENT_BRANCH%", checking out bhss...
  git -C "%ROOT%" checkout bhss
  if errorlevel 1 (
    echo [FAIL] Could not checkout bhss. Resolve manually and re-run.
    exit /b 1
  )
  echo [OK] Switched to bhss.
)

REM ── Step 4: Fix upstream tracking ────────────────────────────
echo [INFO] Setting upstream to origin/bhss...
git -C "%ROOT%" branch --set-upstream-to=origin/bhss bhss
if errorlevel 1 (
  echo [FAIL] Could not set upstream. Does origin/bhss exist?
  exit /b 1
)
echo [OK] Upstream set to origin/bhss.

REM ── Step 5: Pull latest (fast-forward only) ──────────────────
echo [INFO] Pulling latest from origin/bhss (fast-forward only)...
git -C "%ROOT%" pull --ff-only
if errorlevel 1 (
  echo [FAIL] Pull failed. Local commits may diverge from origin/bhss.
  echo        Run: git log --oneline HEAD...origin/bhss
  echo        Then resolve before patching.
  exit /b 1
)
echo [OK] Pull complete.

REM ── Step 6: Show current git state ───────────────────────────
for /f "usebackq delims=" %%C in (`git -C "%ROOT%" rev-parse --short HEAD 2^>nul`) do set "HEAD_SHORT=%%C"
for /f "usebackq delims=" %%B in (`git -C "%ROOT%" rev-parse --abbrev-ref HEAD 2^>nul`) do set "FINAL_BRANCH=%%B"
echo [INFO] Branch: %FINAL_BRANCH%  Commit: %HEAD_SHORT%
echo.

REM ── [DOCKER DISK USAGE] ──────────────────────────────────────
echo [DOCKER DISK USAGE]
docker system df 2>nul
echo.

REM ── [RUNNING CONTAINERS] ─────────────────────────────────────
echo [RUNNING CONTAINERS]
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>nul
echo.

REM ── [CONTAINER DETAILS] restart counts + uptime ──────────────
echo [CONTAINER DETAILS  name / state / restarts / started]
powershell -NoProfile -Command "$names='flowise','flowise-postgres','flowise-proxy','auth-service','accounting-service','bridge-ui'; foreach ($n in $names) { $raw = docker inspect $n 2>$null; if ($LASTEXITCODE -eq 0 -and $raw) { try { $d = ($raw | ConvertFrom-Json)[0]; $st = $d.State.Status; $rc = $d.RestartCount; $sa = $d.State.StartedAt.Substring(0,19); Write-Host ('  {0,-25} {1,-12} restarts={2,-5} since={3}' -f $n, $st, $rc, $sa) } catch { Write-Host ('  {0,-25} inspect-parse-error' -f $n) } } else { Write-Host ('  {0,-25} not found' -f $n) } }"
echo.

REM ── [ENV FILES] presence check ───────────────────────────────
echo [ENV FILES]
for %%S in (auth-service accounting-service flowise flowise-proxy-service-py) do (
  if exist "%ROOT%\%%S\.env" (
    echo   [OK]   %%S\.env
  ) else (
    echo   [MISS] %%S\.env  *** MISSING ***
  )
)
echo.

REM ── Run the comprehensive diagnostic (NEW) ──────────────────
echo [INFO] Running comprehensive BHSS diagnostic...
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\diagnose-bhss-state.ps1"
set "DIAG_EXIT=%ERRORLEVEL%"

echo ============================================================
if "%DIAG_EXIT%"=="0" (
  echo [OK] Diagnostic completed. Review output above.
) else (
  echo [WARN] Diagnostic had issues. Review output above.
)
echo.

REM ── [HTTP SERVICE HEALTH PROBE] localhost endpoints ──────────
echo [HTTP SERVICE HEALTH PROBE]
echo   Probing all services at localhost...
echo.
powershell -NoProfile -Command ^
  "$services = @(" ^
  "  @{name='auth-service';     url='http://localhost:3000/health'}," ^
  "  @{name='accounting-service';url='http://localhost:3001/health'}," ^
  "  @{name='flowise-proxy';    url='http://localhost:8000/health'}," ^
  "  @{name='bridge';           url='http://localhost:3082/'}," ^
  "  @{name='flowise';          url='http://localhost:3002/'}" ^
  "); $allOk=$true;" ^
  "foreach ($svc in $services) {" ^
  "  try {" ^
  "    $r = Invoke-WebRequest -Uri $svc.url -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop;" ^
  "    Write-Host ('  [OK]   {0,-25} HTTP {1}  {2}' -f $svc.name, $r.StatusCode, $svc.url) -ForegroundColor Green" ^
  "  } catch {" ^
  "    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'N/A' };" ^
  "    Write-Host ('  [FAIL] {0,-25} HTTP {1}  {2}' -f $svc.name, $code, $svc.url) -ForegroundColor Red;" ^
  "    $allOk=$false" ^
  "  }" ^
  "};" ^
  "Write-Host '';" ^
  "if ($allOk) { Write-Host '  All services healthy at localhost' -ForegroundColor Green }" ^
  "else { Write-Host '  One or more services NOT responding - check containers above' -ForegroundColor Yellow }"
echo.

REM ── Offer to auto-start services if needed ──────────────────
echo [HEALTH CHECK]
docker ps --format "{{.Names}}" | findstr /i "flowise-proxy" >nul 2>&1
if errorlevel 1 (
  echo [WARN] flowise-proxy not running. Starting services...
  if exist "%ROOT%\flowise-proxy-service-py\docker-compose.yml" (
    cd /d "%ROOT%\flowise-proxy-service-py"
    docker-compose up -d
    if errorlevel 1 (
      echo [FAIL] Could not start flowise-proxy
    ) else (
      echo [OK] flowise-proxy started. Waiting 5 seconds for health check...
      timeout /t 5 /nobreak
    )
  )
) else (
  echo [OK] flowise-proxy is running
)

docker ps --format "{{.Names}}" | findstr /i "auth-service" >nul 2>&1
if errorlevel 1 (
  echo [WARN] auth-service not running. Starting...
  if exist "%ROOT%\auth-service\docker-compose.dev.yml" (
    cd /d "%ROOT%\auth-service"
    docker-compose -f docker-compose.dev.yml up -d
    if errorlevel 1 (
      echo [FAIL] Could not start auth-service
    ) else (
      echo [OK] auth-service started. Waiting 5 seconds for health check...
      timeout /t 5 /nobreak
    )
  )
) else (
  echo [OK] auth-service is running
)

echo.

REM ── Final probe check ───────────────────────────────────────
echo [INFO] Running final machine state probe...
echo ============================================================
call "%ROOT%\probe-machine-state.bat"
set "PROBE_EXIT=%ERRORLEVEL%"

echo ============================================================
if "%PROBE_EXIT%"=="0" (
  echo [OK] Git fix + probe completed successfully. Safe to patch.
  echo.
  echo [NEXT STEP] Run bridge target probe to find flowise-proxy endpoint:
  echo.
  echo   powershell -ExecutionPolicy Bypass -File .\probe-bridge-target.ps1 -PreferredHost "ai01.bhss.edu.hk" -ProxyPort 8000
  echo.
) else (
  echo [FAIL] Probe reported errors. Patch must be aborted.
)
exit /b %PROBE_EXIT%
