@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Fix broken git branch state then run the comprehensive workstation probe.
REM Exit code: 0 = probe passed, 1 = abort.
REM Usage: probe_and_fix.bat

set "ROOT=%~dp0"
set "LOG_DIR=%ROOT%logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo ============================================================
echo  ChatProxy Workstation Git Fix + Probe
echo ============================================================
echo.

REM ── Step 1: Verify git is available ─────────────────────────
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

REM ── Step 6: Show current state ───────────────────────────────
for /f "usebackq delims=" %%C in (`git -C "%ROOT%" rev-parse --short HEAD 2^>nul`) do set "HEAD_SHORT=%%C"
for /f "usebackq delims=" %%B in (`git -C "%ROOT%" rev-parse --abbrev-ref HEAD 2^>nul`) do set "FINAL_BRANCH=%%B"
echo [INFO] Branch: %FINAL_BRANCH%  Commit: %HEAD_SHORT%
echo.

REM ── Step 7: Run the comprehensive probe ──────────────────────
echo [INFO] Running workstation probe...
echo ============================================================
call "%ROOT%probe-machine-state.bat"
set "PROBE_EXIT=%ERRORLEVEL%"

echo ============================================================
if "%PROBE_EXIT%"=="0" (
  echo [OK] Git fix + probe completed successfully. Safe to patch.
) else (
  echo [FAIL] Probe reported errors. Patch must be aborted.
)
exit /b %PROBE_EXIT%
