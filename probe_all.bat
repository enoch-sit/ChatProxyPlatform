@echo off
REM ============================================================================
REM probe_all.bat — Deep diagnostic for LOCAL workstation auth/mongo wiring
REM
REM Captures everything needed to root-cause "auth-service won't connect to
REM MongoDB" or "login returns RST" on a LOCAL deploy. Read-only.
REM
REM Output: logs\probe_all-YYYYMMDD-HHMMSS.txt
REM ============================================================================

setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist logs mkdir logs

for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd-HHmmss'"`) do set TS=%%I
set OUT=logs\probe_all-%TS%.txt

echo ChatProxyPlatform probe_all - %DATE% %TIME%> "%OUT%"
echo ============================================================>> "%OUT%"

call :section "1. HOST"
echo COMPUTERNAME=%COMPUTERNAME%>> "%OUT%"
echo USERNAME=%USERNAME%>> "%OUT%"
echo CWD=%CD%>> "%OUT%"

call :section "2. GIT"
git rev-parse --abbrev-ref HEAD >> "%OUT%" 2>&1
git log -1 --oneline >> "%OUT%" 2>&1
git status --short >> "%OUT%" 2>&1

call :section "3. AUTH-SERVICE .env (key list, no values)"
if exist auth-service\.env (
  powershell -NoProfile -Command "Get-Content auth-service\.env | ForEach-Object { if ($_ -match '^([A-Z_][A-Z0-9_]*)=') { $matches[1] } }" >> "%OUT%" 2>&1
) else (
  echo MISSING auth-service\.env>> "%OUT%"
)

call :section "4. AUTH-SERVICE .env MONGO lines (verbatim)"
if exist auth-service\.env (
  findstr /I "MONGO" auth-service\.env >> "%OUT%" 2>&1
)

call :section "5. AUTH-SERVICE container env (MONGO/NODE/PORT only)"
docker exec auth-service printenv 2>nul | findstr /I "MONGO NODE_ENV PORT JWT" >> "%OUT%" 2>&1
if errorlevel 1 echo (docker exec failed - container may be down or printenv missing)>> "%OUT%"

call :section "6. AUTH-SERVICE container .env file (as seen INSIDE container)"
docker exec auth-service sh -c "ls -la /app/.env 2>&1; echo ---; grep -i MONGO /app/.env 2>&1" >> "%OUT%" 2>&1

call :section "7. AUTH-SERVICE NODE_ENV-driven dotenv path"
echo (auth-service src/app.ts loads .env.production OR .env.samehost OR .env.development based on NODE_ENV)>> "%OUT%"
docker exec auth-service sh -c "echo NODE_ENV=$NODE_ENV; ls -la /app/.env.production /app/.env.samehost /app/.env.development 2>&1" >> "%OUT%" 2>&1

call :section "8. DOCKER PS"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" >> "%OUT%" 2>&1

call :section "9. AUTH-SERVICE LOGS (last 60)"
docker logs auth-service --tail 60 >> "%OUT%" 2>&1

call :section "10. MONGODB-AUTH PING from auth-service container"
docker exec auth-service sh -c "node -e \"require('dns').lookup('mongodb-auth',(e,a)=>console.log('dns:',e?e.code:a))\"" >> "%OUT%" 2>&1
docker exec auth-service sh -c "node -e \"const net=require('net');const s=net.connect(27017,'mongodb-auth',()=>{console.log('tcp:OK');s.end()});s.on('error',e=>console.log('tcp:'+e.code))\"" >> "%OUT%" 2>&1

call :section "11. NETWORKS"
docker network ls >> "%OUT%" 2>&1
echo ---auth-service networks--->> "%OUT%"
docker inspect auth-service --format "{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}" >> "%OUT%" 2>&1
echo.>> "%OUT%"
echo ---mongodb-auth networks--->> "%OUT%"
docker inspect mongodb-auth --format "{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}" >> "%OUT%" 2>&1
echo.>> "%OUT%"

call :section "12. AUTH-SERVICE container created vs .env mtime"
docker inspect auth-service --format "Created: {{.Created}}" >> "%OUT%" 2>&1
if exist auth-service\.env (
  powershell -NoProfile -Command "Get-Item auth-service\.env | Select-Object @{N='envLastWrite';E={$_.LastWriteTime.ToString('o')}} | Format-List" >> "%OUT%" 2>&1
)

call :section "13. ENDPOINT CURL"
curl -s -o nul -w "auth /health   -> HTTP %%{http_code}\n" --max-time 4 http://localhost:3000/health >> "%OUT%" 2>&1
curl -s -o nul -w "auth /api/auth/login (POST) -> HTTP %%{http_code}\n" --max-time 4 -X POST -H "Content-Type: application/json" -d "{}" http://localhost:3000/api/auth/login >> "%OUT%" 2>&1
curl -s -o nul -w "accounting    -> HTTP %%{http_code}\n" --max-time 4 http://localhost:3001/health >> "%OUT%" 2>&1
curl -s -o nul -w "flowise-proxy -> HTTP %%{http_code}\n" --max-time 4 http://localhost:8000/health >> "%OUT%" 2>&1
curl -s -o nul -w "bridge        -> HTTP %%{http_code}\n" --max-time 4 http://localhost:3082/ >> "%OUT%" 2>&1

call :section "DONE"
echo Wrote %OUT%
type "%OUT%"
endlocal
exit /b 0

:section
echo.>> "%OUT%"
echo === %~1 ===>> "%OUT%"
goto :eof
