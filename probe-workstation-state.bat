@echo off
REM probe-workstation-state.bat
REM Comprehensive workstation diagnostics - run this on the remote machine to gather state information
REM Usage: probe-workstation-state.bat > workstation-state.log 2>&1

setlocal enabledelayedexpansion
cd /d %~dp0

echo ====================================================================
echo  Workstation State Probe - ChatProxy Platform
echo ====================================================================
echo  Machine: %COMPUTERNAME%
echo  User: %USERNAME%
echo  Time: %date% %time%
echo.

REM ── System Info ──────────────────────────────────────────────────────
echo [SYSTEM INFO]
systeminfo | find /i "Computer Name" | find /v "DNS"
systeminfo | find /i "OS Version"
systeminfo | find /i "System Boot Time"
echo.

REM ── Network Configuration ────────────────────────────────────────────
echo [NETWORK CONFIGURATION]
ipconfig /all
echo.

REM ── WireGuard Interface ──────────────────────────────────────────────
echo [WIREGUARD STATUS]
if exist "C:\Program Files\WireGuard\wg.exe" (
    "C:\Program Files\WireGuard\wg.exe" show
) else (
    echo WireGuard CLI not found at default path
)
echo.

REM ── OpenSSH Service ──────────────────────────────────────────────────
echo [OPENSSH SERVICE STATUS]
sc query sshd
echo.

REM ── SSH Connectivity Test ───────────────────────────────────────────
echo [SSH CONNECTIVITY TEST]
netstat -an | find "22"
echo.

REM ── Docker Status ───────────────────────────────────────────────────
echo [DOCKER STATUS]
docker --version 2>nul || echo Docker not found
docker ps --all 2>nul || echo Docker ps failed
echo.

REM ── Container Status ────────────────────────────────────────────────
echo [CONTAINER STATUS]
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>nul || echo Could not list containers
echo.

REM ── Services ────────────────────────────────────────────────────────
echo [SERVICES]
tasklist /svc | find /i "docker" || echo Docker process not running
echo.

REM ── Firewall ────────────────────────────────────────────────────────
echo [WINDOWS FIREWALL RULES - SSH]
netsh advfirewall firewall show rule name="SSH*" dir=in
echo.

REM ── Routes ──────────────────────────────────────────────────────────
echo [ROUTING TABLE]
route print
echo.

REM ── Disk Space ──────────────────────────────────────────────────────
echo [DISK SPACE]
wmic logicaldisk get name, size, freespace
echo.

REM ── Environment Variables ───────────────────────────────────────────
echo [KEY ENVIRONMENT VARIABLES]
echo PATH length: %PATH:~0,80%...
echo DOCKER_HOST: %DOCKER_HOST%
echo.

REM ── .env Files ──────────────────────────────────────────────────────
echo [.ENV FILES CHECK]
if exist "auth-service\.env" (
    echo auth-service\.env exists
    dir "auth-service\.env"
) else (
    echo auth-service\.env NOT FOUND
)
if exist "bridge\.env" (
    echo bridge\.env exists
    dir "bridge\.env"
) else (
    echo bridge\.env NOT FOUND
)
echo.

REM ── Service Logs ────────────────────────────────────────────────────
echo [DOCKER LOGS - Last 30 lines per service]
for /f "delims=" %%i in ('docker ps -q 2^>nul') do (
    echo.
    echo --- Container: %%i ---
    docker logs --tail 30 %%i 2>nul
)
echo.

REM ── Port Availability ───────────────────────────────────────────────
echo [PORT AVAILABILITY]
netstat -ano | find "LISTENING"
echo.

REM ── Processes ───────────────────────────────────────────────────────
echo [KEY PROCESSES]
tasklist | find /i "docker"
tasklist | find /i "node"
tasklist | find /i "python"
tasklist | find /i "ssh"
echo.

REM ── Git Status ──────────────────────────────────────────────────────
echo [GIT STATUS]
git --version 2>nul || echo Git not found
if exist ".git" (
    git branch --show-current
    git log --oneline -3
) else (
    echo Not in a git repository
)
echo.

REM ── Timestamp ───────────────────────────────────────────────────────
echo [PROBE COMPLETE]
echo Time: %date% %time%
echo.
echo === Output saved to workstation-state.log ===
echo === To send back to management machine: ===
echo === cat workstation-state.log ^| ssh -i fleet_ed25519 fleet@10.10.0.3 "cat > workstation-state-from-remote.log" ===
echo.
