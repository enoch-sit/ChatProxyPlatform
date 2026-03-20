@echo off
REM ============================================================================
REM ChatProxy Platform - Target Machine State Scanner
REM Purpose: Report current git branch, container state, .env configs, and
REM          system health BEFORE switching from main to release/aws branch.
REM Run this script on the TARGET machine prior to executing
REM switch_to_release_aws.bat
REM ============================================================================

setlocal enabledelayedexpansion

title ChatProxy Platform - Target Machine Scanner

echo.
echo ╔════════════════════════════════════════════════════════════════════════╗
echo ║         ChatProxy Platform - Target Machine Scanner                    ║
echo ║         Checking system state before branch migration...               ║
echo ╚════════════════════════════════════════════════════════════════════════╝
echo.

REM ---- Timestamp for output file ----
set "TS=%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "TS=%TS: =0%"
set "OUTPUT_FILE=scan_report_%TS%.txt"

echo [INFO] Report will be saved to: %OUTPUT_FILE%
echo.

call :log "=========================================="
call :log "ChatProxy Platform - Target Machine Scan"
call :log "Generated: %date% %time%"
call :log "Machine: %COMPUTERNAME%"
call :log "User:     %USERNAME%"
call :log "=========================================="
call :log ""

REM ============================================================================
REM SECTION 1: Git Repository Status
REM ============================================================================
call :section "1" "Git Repository Status"

call :log "[Current branch]"
for /f "tokens=*" %%b in ('git branch --show-current 2^>^&1') do (
    set "CURRENT_BRANCH=%%b"
    call :log_info "Branch: %%b"
)

if "!CURRENT_BRANCH!"=="main" (
    call :log_success "On 'main' branch - ready to migrate"
) else if "!CURRENT_BRANCH!"=="release/aws" (
    call :log_warning "Already on 'release/aws' branch - migration may already be done"
) else (
    call :log_warning "On unexpected branch: !CURRENT_BRANCH! (expected 'main')"
)

call :log ""
call :log "[Uncommitted local changes]"
git status --short > temp_gitstatus.txt 2>&1
set "CHANGED_FILES=0"
for /f %%i in ('type temp_gitstatus.txt ^| find /C /V ""') do set "CHANGED_FILES=%%i"
if !CHANGED_FILES! GTR 0 (
    call :log_warning "!CHANGED_FILES! uncommitted or untracked file(s) detected:"
    for /f "tokens=*" %%l in (temp_gitstatus.txt) do call :log_warning "  %%l"
) else (
    call :log_success "Working tree is clean"
)
del temp_gitstatus.txt 2>nul

call :log ""
call :log "[Last 5 commits on current branch]"
for /f "tokens=*" %%l in ('git log --oneline -5 2^>^&1') do call :log_info "  %%l"

call :log ""
call :log "[Remote tracking status]"
for /f "tokens=*" %%l in ('git status -sb 2^>^&1 ^| findstr /C:"##"') do call :log_info "  %%l"

call :log ""
call :log "[Branches available locally and remotely]"
for /f "tokens=*" %%l in ('git branch -a 2^>^&1') do call :log_info "  %%l"

REM ============================================================================
REM SECTION 2: Docker Prerequisites
REM ============================================================================
call :section "2" "Docker Prerequisites"

call :log "[Docker version]"
docker --version >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker NOT found - required to run services"
) else (
    for /f "tokens=*" %%v in ('docker --version 2^>^&1') do call :log_success "%%v"
)

call :log ""
call :log "[Docker Compose version]"
docker compose version >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker Compose NOT available"
) else (
    for /f "tokens=*" %%v in ('docker compose version 2^>^&1') do call :log_success "%%v"
)

call :log ""
call :log "[Docker daemon running]"
docker info >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker daemon is NOT running - start Docker Desktop first"
) else (
    call :log_success "Docker daemon is running"
)

REM ============================================================================
REM SECTION 3: Running Containers
REM ============================================================================
call :section "3" "Running Containers"

call :log "[All running containers]"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" > temp_ps.txt 2>&1
for /f "skip=1 tokens=*" %%l in (temp_ps.txt) do call :log_info "  %%l"
del temp_ps.txt 2>nul

call :log ""
call :log "[Expected service containers]"
set "CONTAINERS=flowise flowise-postgres auth-service mongodb-auth accounting-service postgres-accounting flowise-proxy mongodb-proxy bridge-ui"
set "RUNNING_COUNT=0"
set "STOPPED_COUNT=0"

for %%c in (%CONTAINERS%) do (
    docker ps --filter "name=%%c" --format "{{.Status}}" 2>nul | findstr /C:"Up" >nul 2>&1
    if errorlevel 1 (
        docker ps -a --filter "name=%%c" --format "{{.Names}}" 2>nul | findstr /C:"%%c" >nul 2>&1
        if errorlevel 1 (
            call :log_warning "  %%c: NOT FOUND (container does not exist)"
        ) else (
            call :log_error "  %%c: STOPPED (exists but not running)"
            set /a STOPPED_COUNT+=1
        )
    ) else (
        for /f "tokens=*" %%s in ('docker ps --filter "name=%%c" --format "{{.Status}}" 2^>nul') do (
            echo %%s | findstr /C:"healthy" >nul 2>&1
            if errorlevel 1 (
                call :log_warning "  %%c: %%s (not yet healthy)"
            ) else (
                call :log_success "  %%c: %%s"
            )
        )
        set /a RUNNING_COUNT+=1
    )
)
call :log_info "Summary: !RUNNING_COUNT! running, !STOPPED_COUNT! stopped"

REM ============================================================================
REM SECTION 4: Service Health Endpoints
REM ============================================================================
call :section "4" "Service Health Endpoints"

call :check_endpoint "Auth Service"      "http://localhost:3000/health"
call :check_endpoint "Accounting Service" "http://localhost:3001/health"
call :check_endpoint "Flowise Proxy"     "http://localhost:8000/health"
call :check_endpoint "Flowise"           "http://localhost:3002"
call :check_endpoint "Bridge UI"         "http://localhost:3082"

REM ============================================================================
REM SECTION 5: Environment (.env) Files
REM ============================================================================
call :section "5" "Environment Files"

call :log "[Checking .env file presence per service]"
set "SERVICES=flowise auth-service accounting-service flowise-proxy-service-py bridge"
set "MISSING_ENVS=0"

for %%s in (%SERVICES%) do (
    if exist "%%s\.env" (
        call :log_success "  %%s\.env - EXISTS"
    ) else (
        call :log_error "  %%s\.env - MISSING"
        set /a MISSING_ENVS+=1
    )
    if exist "%%s\.env.example" (
        call :log_info "  %%s\.env.example - EXISTS (reference available)"
    )
)

if !MISSING_ENVS! GTR 0 (
    call :log_error "!MISSING_ENVS! .env file(s) missing - services will fail to start"
)

REM ============================================================================
REM SECTION 6: Key Environment Variable Values
REM ============================================================================
call :section "6" "Key Environment Variable Values"

call :log "[NODE_ENV per service - expected: development on main]"
call :check_env_var "auth-service" "NODE_ENV"
call :check_env_var "accounting-service" "NODE_ENV"
call :check_env_var "flowise-proxy-service-py" "DEBUG"

call :log ""
call :log "[CORS_ORIGIN - check for localhost values]"
call :check_env_var "auth-service" "CORS_ORIGIN"

call :log ""
call :log "[SMTP/Email config - check for mailhog vs SES]"
call :check_env_var "auth-service" "SMTP_HOST"
call :check_env_var "auth-service" "EMAIL_SERVICE"

call :log ""
call :log "[Bridge frontend API URL]"
call :check_env_var "bridge" "VITE_FLOWISE_PROXY_API_URL"

call :log ""
call :log "[JWT secrets presence (values masked)]"
call :check_secret_set "auth-service" "JWT_ACCESS_SECRET"
call :check_secret_set "accounting-service" "JWT_ACCESS_SECRET"
call :check_secret_set "flowise-proxy-service-py" "JWT_SECRET_KEY"
call :check_secret_set "flowise-proxy-service-py" "JWT_ACCESS_SECRET"

call :log ""
call :log "[JWT secret consistency across services]"
set "JWT_AUTH="
set "JWT_ACC="
set "JWT_PROXY="
if exist "auth-service\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" auth-service\.env 2^>nul') do set "JWT_AUTH=%%a"
)
if exist "accounting-service\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" accounting-service\.env 2^>nul') do set "JWT_ACC=%%a"
)
if exist "flowise-proxy-service-py\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" flowise-proxy-service-py\.env 2^>nul') do set "JWT_PROXY=%%a"
)
if "!JWT_AUTH!"=="" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_SECRET_KEY=" flowise-proxy-service-py\.env 2^>nul') do set "JWT_PROXY=%%a"
)

if "!JWT_AUTH!"=="!JWT_ACC!" if "!JWT_ACC!"=="!JWT_PROXY!" (
    call :log_success "JWT secrets MATCH across all 3 services"
) else (
    call :log_warning "JWT secrets may differ between services - verify with generate_secrets.bat"
)

REM ============================================================================
REM SECTION 7: Dockerfile Versions in Use
REM ============================================================================
call :section "7" "Dockerfile Versions (dev vs prod)"

call :log "[auth-service]"
if exist "auth-service\Dockerfile.prod" (
    call :log_info "  Dockerfile.prod EXISTS (will be used by release/aws)"
) else (
    call :log_warning "  Dockerfile.prod NOT found"
)
if exist "auth-service\Dockerfile" (
    call :log_info "  Dockerfile (dev) EXISTS (used by main branch)"
)

call :log ""
call :log "[Compose file being used by auth-service]"
if exist "auth-service\docker-compose.dev.yml" (
    call :log_info "  docker-compose.dev.yml EXISTS (main dev file)"
)
if exist "auth-service\docker-compose.prod.yml" (
    call :log_warning "  docker-compose.prod.yml EXISTS - may be used by release/aws"
)

call :log ""
call :log "[accounting-service]"
if exist "accounting-service\Dockerfile" (
    call :log_info "  Dockerfile EXISTS"
)
if exist "accounting-service\Dockerfile.prod" (
    call :log_info "  Dockerfile.prod EXISTS"
)

call :log ""
call :log "[flowise-proxy-service-py]"
if exist "flowise-proxy-service-py\Dockerfile" (
    call :log_info "  Dockerfile EXISTS"
)

call :log ""
call :log "[bridge]"
if exist "bridge\Dockerfile" (
    call :log_info "  Dockerfile EXISTS"
)
if exist "bridge\docker-compose.yml" (
    call :log_info "  docker-compose.yml EXISTS"
)

REM ============================================================================
REM SECTION 8: Disk and Volume Check
REM ============================================================================
call :section "8" "Disk Space and Docker Volumes (D: drive focus)"

call :log "[Docker disk usage]"
docker system df > temp_df.txt 2>&1
for /f "tokens=*" %%l in (temp_df.txt) do call :log_info "  %%l"
del temp_df.txt 2>nul

call :log ""
call :log "[D: drive availability (data volumes)]"
for /f "skip=1 tokens=1,2,3" %%a in ('wmic logicaldisk where "DeviceID='D:'" get DeviceID^,FreeSpace^,Size 2^>nul') do (
    if not "%%a"=="" (
        set /a "FREE_GB=%%b / 1073741824"
        set /a "TOTAL_GB=%%c / 1073741824"
        call :log_info "  D: Drive - Free: !FREE_GB! GB  /  Total: !TOTAL_GB! GB"
    )
)

call :log ""
call :log "[C: drive availability]"
for /f "skip=1 tokens=1,2,3" %%a in ('wmic logicaldisk where "DeviceID='C:'" get DeviceID^,FreeSpace^,Size 2^>nul') do (
    if not "%%a"=="" (
        set /a "FREE_GB=%%b / 1073741824"
        call :log_info "  C: Drive - Free: !FREE_GB! GB"
        if !FREE_GB! LSS 5 (
            call :log_warning "  Low disk space on C: - Docker builds may fail"
        )
    )
)

call :log ""
call :log "[Available RAM]"
for /f "skip=1 tokens=*" %%a in ('wmic OS get FreePhysicalMemory 2^>nul') do (
    if not "%%a"=="" (
        set /a "FREE_MB=%%a / 1024"
        call :log_info "  Free RAM: !FREE_MB! MB"
        if !FREE_MB! LSS 1024 (
            call :log_warning "  Low RAM - consider stopping non-essential apps before rebuild"
        )
    )
)

REM ============================================================================
REM SECTION 9: Docker Networks
REM ============================================================================
call :section "9" "Docker Networks"

docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" > temp_net.txt 2>&1
for /f "tokens=*" %%l in (temp_net.txt) do call :log_info "  %%l"
del temp_net.txt 2>nul

call :log ""
docker network ls | findstr /C:"chatproxy" >nul 2>&1
if errorlevel 1 (
    call :log_warning "No 'chatproxy' network found - services may not be running yet"
) else (
    call :log_success "chatproxy network exists"
)

REM ============================================================================
REM SECTION 10: .env.example vs .env diff (new keys that may appear after checkout)
REM ============================================================================
call :section "10" "Environment Variable Coverage (.env.example vs .env)"
call :log "[Checking which keys in .env.example are missing from .env]"
call :log "[These are variables you will need to set after git checkout release/aws]"
call :log ""

for %%s in (auth-service accounting-service flowise-proxy-service-py bridge flowise) do (
    if exist "%%s\.env.example" (
        if exist "%%s\.env" (
            call :log "  [%%s]"
            for /f "eol=# tokens=1 delims==" %%k in ('findstr /v "^#" "%%s\.env.example" 2^>nul ^| findstr /v "^$"') do (
                if not "%%k"=="" (
                    findstr /B /C:"%%k=" "%%s\.env" >nul 2>&1
                    if errorlevel 1 (
                        call :log_warning "    MISSING in .env: %%k"
                    )
                )
            )
        ) else (
            call :log_error "  [%%s] - .env missing, cannot compare"
        )
    ) else (
        call :log_info "  [%%s] - no .env.example found"
    )
)

REM ============================================================================
REM SECTION 11: Summary & Go/No-Go Assessment
REM ============================================================================
call :section "11" "Summary and Migration Readiness"

set "ERROR_COUNT=0"
set "WARNING_COUNT=0"
for /f %%i in ('findstr /C:"[ERROR]" "%OUTPUT_FILE%" 2^>nul ^| find /C "[ERROR]"') do set "ERROR_COUNT=%%i"
for /f %%i in ('findstr /C:"[WARNING]" "%OUTPUT_FILE%" 2^>nul ^| find /C "[WARNING]"') do set "WARNING_COUNT=%%i"

call :log ""
call :log "Errors found:   !ERROR_COUNT!"
call :log "Warnings found: !WARNING_COUNT!"
call :log ""

if !ERROR_COUNT! EQU 0 (
    if !WARNING_COUNT! EQU 0 (
        call :log_success "GO: System is clean - ready to run switch_to_release_aws.bat"
    ) else (
        call :log_warning "CAUTION: !WARNING_COUNT! warning(s) - review before proceeding"
        call :log_warning "Run switch_to_release_aws.bat only after reviewing warnings above"
    )
) else (
    call :log_error "NO-GO: !ERROR_COUNT! error(s) must be resolved before migrating"
    call :log ""
    call :log "Common fixes:"
    findstr /C:"Docker daemon is NOT running" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 call :log "  - Start Docker Desktop, wait for it to fully load"
    findstr /C:".env - MISSING" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 call :log "  - Run setup_env_files.bat to create missing .env files"
    findstr /C:"STOPPED" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 call :log "  - Restart stopped containers: cd [service] && docker compose up -d"
)

call :log ""
call :log "Next step: switch_to_release_aws.bat"
call :log "=========================================="
call :log "End of Target Machine Scan"
call :log "=========================================="

echo.
echo ════════════════════════════════════════════════════════════════════════
echo  Scan complete - Report: %OUTPUT_FILE%
echo  Errors: %ERROR_COUNT%   Warnings: %WARNING_COUNT%
echo ════════════════════════════════════════════════════════════════════════
echo.
if %ERROR_COUNT% GTR 0 (
    echo [31m[NO-GO][0m Resolve errors before switching branches.
) else if %WARNING_COUNT% GTR 0 (
    echo [33m[CAUTION][0m Review warnings above, then run: switch_to_release_aws.bat
) else (
    echo [32m[GO][0m Run: switch_to_release_aws.bat
)
echo.

pause
exit /b %ERROR_COUNT%

REM ============================================================================
REM Helper Functions
REM ============================================================================

:section
call :log ""
call :log "=========================================="
call :log "SECTION %~1: %~2"
call :log "=========================================="
call :log ""
goto :eof

:log
echo %~1
echo %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_success
echo [32m[OK][0m %~1
echo [OK] %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_error
echo [31m[ERROR][0m %~1
echo [ERROR] %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_warning
echo [33m[WARN][0m %~1
echo [WARN] %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_info
echo [36m[INFO][0m %~1
echo [INFO] %~1 >> "%OUTPUT_FILE%"
goto :eof

:check_endpoint
set "_SVC=%~1"
set "_URL=%~2"
curl -s -o nul -w "%%{http_code}" "%_URL%" --max-time 5 > temp_ep.txt 2>&1
set /p _STATUS=<temp_ep.txt
del temp_ep.txt 2>nul
if "%_STATUS%"=="200" (
    call :log_success "  %_SVC%: [200 OK] %_URL%"
) else if "%_STATUS%"=="000" (
    call :log_error "  %_SVC%: [NOT REACHABLE] %_URL%"
) else (
    call :log_warning "  %_SVC%: [HTTP %_STATUS%] %_URL%"
)
goto :eof

:check_env_var
set "_DIR=%~1"
set "_KEY=%~2"
if exist "%_DIR%\.env" (
    for /f "tokens=2 delims==" %%v in ('findstr /B /C:"%_KEY%=" "%_DIR%\.env" 2^>nul') do (
        call :log_info "  %_DIR% %_KEY%=%%v"
        goto :eof
    )
    call :log_warning "  %_DIR% %_KEY%=(not set)"
) else (
    call :log_error "  %_DIR% .env not found"
)
goto :eof

:check_secret_set
set "_DIR=%~1"
set "_KEY=%~2"
if exist "%_DIR%\.env" (
    for /f "tokens=2 delims==" %%v in ('findstr /B /C:"%_KEY%=" "%_DIR%\.env" 2^>nul') do (
        if "%%v"=="" (
            call :log_error "  %_DIR% %_KEY%=(empty)"
        ) else (
            call :log_success "  %_DIR% %_KEY%=****(set)"
        )
        goto :eof
    )
    call :log_warning "  %_DIR% %_KEY%=(not present in file)"
) else (
    call :log_error "  %_DIR% .env not found"
)
goto :eof
