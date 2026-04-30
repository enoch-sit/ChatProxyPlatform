@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM  probe_state.bat
REM  Read-only diagnostic for a Windows workstation running
REM  ChatProxyPlatform (deploy/localdeploy or any branch).
REM  Captures host, git, docker, services, env, and log state
REM  to a single text file for paste-back analysis.
REM
REM  Safe: NEVER prints secret values, only key names + sha-of-value.
REM  Safe: NEVER writes anything outside logs/.
REM ============================================================

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "LOG_DIR=%ROOT%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%I"
set "OUT=%LOG_DIR%\probe_state-%TS%.txt"

echo ============================================================ > "%OUT%"
echo  ChatProxy probe_state.bat                                    >> "%OUT%"
echo  Time: %TS%                                                   >> "%OUT%"
echo ============================================================ >> "%OUT%"
echo. >> "%OUT%"

echo [SECTION] Host >> "%OUT%"
echo COMPUTERNAME=%COMPUTERNAME% >> "%OUT%"
echo USERNAME=%USERNAME% >> "%OUT%"
echo USERPROFILE=%USERPROFILE% >> "%OUT%"
echo CWD=%ROOT% >> "%OUT%"
powershell -NoProfile -Command "(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture | Format-List | Out-String).Trim()" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Git >> "%OUT%"
git -C "%ROOT%" rev-parse --abbrev-ref HEAD          >> "%OUT%" 2>&1
git -C "%ROOT%" rev-parse HEAD                       >> "%OUT%" 2>&1
git -C "%ROOT%" rev-parse --abbrev-ref --symbolic-full-name @{u} >> "%OUT%" 2>&1
echo --- upstream HEAD --- >> "%OUT%"
git -C "%ROOT%" log -1 --format="%%H %%s" @{u}       >> "%OUT%" 2>&1
echo --- last 10 commits --- >> "%OUT%"
git -C "%ROOT%" log --oneline -n 10                  >> "%OUT%" 2>&1
echo --- ahead/behind upstream --- >> "%OUT%"
git -C "%ROOT%" rev-list --left-right --count @{u}...HEAD >> "%OUT%" 2>&1
echo --- dirty files --- >> "%OUT%"
git -C "%ROOT%" status --porcelain                   >> "%OUT%" 2>&1
echo --- remotes --- >> "%OUT%"
git -C "%ROOT%" remote -v                            >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Repo files of interest >> "%OUT%"
for %%F in (
  patch.ps1
  patch-windows-workstation.bat
  patch_and_migrate.bat
  probe-machine-state.bat
  check-patch-drift.ps1
  fleet-inventory.json
  workstation-manifest.json
  version.json
  setup.ps1
  diagnose.ps1
  scripts\backfill-accounting-users.ps1
) do (
  if exist "%ROOT%\%%F" (
    echo PRESENT  %%F >> "%OUT%"
  ) else (
    echo MISSING  %%F >> "%OUT%"
  )
)
echo. >> "%OUT%"

echo [SECTION] Service .env files (presence + key count, no values) >> "%OUT%"
for %%S in (auth-service accounting-service flowise-proxy-service-py flowise bridge) do (
  if exist "%ROOT%\%%S\.env" (
    for /f %%C in ('powershell -NoProfile -Command "(Get-Content '%ROOT%\%%S\.env' ^| Where-Object { $_ -match '^[A-Z_]+=' } ^| Measure-Object).Count"') do echo PRESENT  %%S\.env  keys=%%C >> "%OUT%"
  ) else (
    echo MISSING  %%S\.env >> "%OUT%"
  )
)
echo. >> "%OUT%"

echo [SECTION] Docker daemon >> "%OUT%"
docker version --format "Client: {{.Client.Version}}  Server: {{.Server.Version}}" >> "%OUT%" 2>&1
docker info --format "Containers: {{.Containers}}  Running: {{.ContainersRunning}}  Images: {{.Images}}" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Docker containers (all) >> "%OUT%"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Docker volumes >> "%OUT%"
docker volume ls --format "table {{.Name}}\t{{.Driver}}" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Docker networks >> "%OUT%"
docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Service endpoint reachability >> "%OUT%"
for %%E in (
  "auth=http://localhost:3000/health"
  "accounting=http://localhost:3001/health"
  "flowise=http://localhost:3002/api/v1/ping"
  "flowise-proxy=http://localhost:8000/health"
  "bridge=http://localhost:3082/"
) do (
  for /f "tokens=1,2 delims==" %%a in (%%E) do (
    powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri '%%b' -UseBasicParsing -TimeoutSec 4; Write-Output ('OK    %%a {0}  status={1}' -f '%%b', $r.StatusCode) } catch { Write-Output ('FAIL  %%a %%b  ' + $_.Exception.Message.Split([Environment]::NewLine)[0]) }" >> "%OUT%" 2>&1
  )
)
echo. >> "%OUT%"

echo [SECTION] Image tags currently in use >> "%OUT%"
docker ps -a --format "{{.Names}}|{{.Image}}" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Recent logs in logs\ (last 10 by mtime) >> "%OUT%"
powershell -NoProfile -Command "if (Test-Path '%LOG_DIR%') { Get-ChildItem '%LOG_DIR%' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object { '{0,-40} {1,12} bytes  {2}' -f $_.Name, $_.Length, $_.LastWriteTime } }" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] Disk free on %SystemDrive% >> "%OUT%"
powershell -NoProfile -Command "$d = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')); ('Free: {0:N1} GB / Used: {1:N1} GB' -f ($d.Free/1GB), ($d.Used/1GB))" >> "%OUT%" 2>&1
echo. >> "%OUT%"

echo [SECTION] BHSS-specific markers (should be absent on non-BHSS) >> "%OUT%"
findstr /m /i "ai01.bhss.edu.hk" "%ROOT%\*.json" "%ROOT%\*.conf" 2>nul >> "%OUT%"
if exist "%ROOT%\probe_and_fix_bhss.bat" echo PRESENT  probe_and_fix_bhss.bat >> "%OUT%"
if exist "%ROOT%\diagnose-bhss-state.ps1" echo PRESENT  diagnose-bhss-state.ps1 >> "%OUT%"
echo. >> "%OUT%"

echo ============================================================ >> "%OUT%"
echo  Probe complete                                              >> "%OUT%"
echo ============================================================ >> "%OUT%"

type "%OUT%"
echo.
echo [OK] State written to: %OUT%
echo [INFO] Paste the contents of that file back to the assistant.
endlocal
exit /b 0
