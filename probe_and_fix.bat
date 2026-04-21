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
for /f %%N in ('git -C "%ROOT%" rev-list --count HEAD..origin/main 2^>nul') do set "PENDING_COUNT=%%N"
if "%PENDING_COUNT%"=="0" (
  echo [OK] No pending commits on origin/main.
) else (
  echo [INFO] %PENDING_COUNT% commits available on origin/main:
  git -C "%ROOT%" log --oneline HEAD..origin/main
)
echo.

REM ── Step 3: Switch to main ───────────────────────────────────
echo [INFO] Switching to main branch...
for /f "usebackq delims=" %%B in (`git -C "%ROOT%" rev-parse --abbrev-ref HEAD 2^>nul`) do set "CURRENT_BRANCH=%%B"

if /i "%CURRENT_BRANCH%"=="main" (
  echo [OK] Already on main.
) else (
  echo [INFO] Currently on "%CURRENT_BRANCH%", checking out main...
  git -C "%ROOT%" checkout main
  if errorlevel 1 (
    echo [FAIL] Could not checkout main. Resolve manually and re-run.
    exit /b 1
  )
  echo [OK] Switched to main.
)

REM ── Step 4: Fix upstream tracking ────────────────────────────
echo [INFO] Setting upstream to origin/main...
git -C "%ROOT%" branch --set-upstream-to=origin/main main
if errorlevel 1 (
  echo [FAIL] Could not set upstream. Does origin/main exist?
  exit /b 1
)
echo [OK] Upstream set to origin/main.

REM ── Step 5: Pull latest (fast-forward only) ──────────────────
echo [INFO] Pulling latest from origin/main (fast-forward only)...
git -C "%ROOT%" pull --ff-only
if errorlevel 1 (
  echo [FAIL] Pull failed. Local commits may diverge from origin/main.
  echo        Run: git log --oneline HEAD...origin/main
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
powershell -NoProfile -Command "$names='flowise','flowise-postgres','flowise-proxy','auth-service','accounting-service','bridge'; foreach ($n in $names) { $raw = docker inspect $n 2>$null; if ($LASTEXITCODE -eq 0 -and $raw) { try { $d = ($raw | ConvertFrom-Json)[0]; $st = $d.State.Status; $rc = $d.RestartCount; $sa = $d.State.StartedAt.Substring(0,19); Write-Host ('  {0,-25} {1,-12} restarts={2,-5} since={3}' -f $n, $st, $rc, $sa) } catch { Write-Host ('  {0,-25} inspect-parse-error' -f $n) } } else { Write-Host ('  {0,-25} not found' -f $n) } }"
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

REM ── Run the comprehensive probe ───────────────────────────────
echo [INFO] Running comprehensive workstation probe...
echo ============================================================
call "%ROOT%\probe-machine-state.bat"
set "PROBE_EXIT=%ERRORLEVEL%"

echo ============================================================
if "%PROBE_EXIT%"=="0" (
  echo [OK] Git fix + probe completed successfully. Safe to patch.
) else (
  echo [FAIL] Probe reported errors. Patch must be aborted.
)
exit /b %PROBE_EXIT%
exit /b %PROBE_EXIT%
