@echo off
REM ============================================================================
REM ChatProxy Platform - Switch to release/aws Branch (Local Run)
REM
REM This script migrates the target Windows machine from the 'main' branch
REM (local dev mode) to the 'release/aws' branch, running the services
REM LOCALLY (not deploying to real AWS).
REM
REM BEFORE RUNNING: run scan_target.bat and confirm GO status.
REM
REM Phases:
REM   Phase 2 - Backup .env files + gracefully stop all containers
REM   Phase 3 - Git fetch, stash, checkout release/aws, pull
REM   Phase 4 - Detect new .env keys, patch .env files for local run
REM   Phase 5 - Rebuild Docker images (using Dockerfile.prod where available)
REM   Phase 6 - Start services + verify health endpoints
REM ============================================================================

setlocal enabledelayedexpansion

title ChatProxy Platform - Switch to release/aws

echo.
echo ╔════════════════════════════════════════════════════════════════════════╗
echo ║      ChatProxy Platform - Switch to release/aws Branch                ║
echo ║      LOCAL run mode (not deploying to real AWS)                        ║
echo ╚════════════════════════════════════════════════════════════════════════╝
echo.

set "TS=%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
set "TS=%TS: =0%"
set "OUTPUT_FILE=switch_log_%TS%.txt"
set "BACKUP_DIR=backup_env_%TS%"
set "ERRORS=0"

call :log "Switch to release/aws log - %date% %time%"
call :log "Machine: %COMPUTERNAME% / User: %USERNAME%"
call :log ""

REM ============================================================================
REM PRE-FLIGHT CHECK
REM ============================================================================
call :header "PRE-FLIGHT CHECK"

call :log "[Confirm git repo and Docker are available]"

git branch --show-current >nul 2>&1
if errorlevel 1 (
    call :log_error "Not in a git repository. Run this script from the project root."
    goto :abort
)

docker info >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker daemon is not running. Start Docker Desktop first."
    goto :abort
)
call :log_success "Docker running"

for /f "tokens=*" %%b in ('git branch --show-current 2^>^&1') do set "CURRENT_BRANCH=%%b"
call :log_info "Current branch: !CURRENT_BRANCH!"

if "!CURRENT_BRANCH!"=="release/aws" (
    echo.
    call :log_warning "Already on 'release/aws'. Did you mean to re-run?"
    echo.
    set /p "CONT=Continue anyway? (y/N): "
    if /i not "!CONT!"=="y" goto :abort
)

echo.
echo ════════════════════════════════════════════════════════════════════════
echo  This script will:
echo    1. Backup all .env files to %BACKUP_DIR%\
echo    2. Stop all running containers (docker compose down)
echo    3. Switch git branch to release/aws
echo    4. Patch .env files for LOCAL mode (databases stay local)
echo    5. Rebuild all Docker images
echo    6. Start services and run health checks
echo.
echo  NOTE: NO real AWS resources will be touched.
echo ════════════════════════════════════════════════════════════════════════
echo.
set /p "READY=Proceed? (y/N): "
if /i not "!READY!"=="y" (
    echo Aborted by user.
    goto :eof
)

REM ============================================================================
REM PHASE 2: Backup .env files + Stop Containers
REM ============================================================================
call :header "PHASE 2 - Backup .env Files"

mkdir "%BACKUP_DIR%" 2>nul
set "ENV_SERVICES=flowise auth-service accounting-service flowise-proxy-service-py bridge"

for %%s in (%ENV_SERVICES%) do (
    if exist "%%s\.env" (
        mkdir "%BACKUP_DIR%\%%s" 2>nul
        copy /Y "%%s\.env" "%BACKUP_DIR%\%%s\.env" >nul
        call :log_success "Backed up %%s\.env -> %BACKUP_DIR%\%%s\.env"
    ) else (
        call :log_warning "%%s\.env not found - skipping backup"
    )
    if exist "%%s\.env.backup" (
        copy /Y "%%s\.env.backup" "%BACKUP_DIR%\%%s\.env.backup" >nul
    )
)
call :log_success "All .env files backed up to %BACKUP_DIR%\"

echo.
call :header "PHASE 2 (cont.) - Stop All Containers"

call :log "[Stopping auth-service (docker-compose.dev.yml)]"
if exist "auth-service\docker-compose.dev.yml" (
    pushd auth-service
    docker compose -f docker-compose.dev.yml down
    if errorlevel 1 (
        call :log_warning "auth-service compose down returned non-zero (may already be stopped)"
    ) else (
        call :log_success "auth-service stopped"
    )
    popd
)

for %%s in (accounting-service flowise-proxy-service-py bridge flowise) do (
    call :log "[Stopping %%s]"
    if exist "%%s\docker-compose.yml" (
        pushd %%s
        docker compose down
        if errorlevel 1 (
            call :log_warning "%%s compose down returned non-zero (may already be stopped)"
        ) else (
            call :log_success "%%s stopped"
        )
        popd
    ) else (
        call :log_warning "%%s\docker-compose.yml not found - skipping"
    )
)

call :log ""
call :log "[Remaining running containers after shutdown]"
docker ps --format "  {{.Names}} - {{.Status}}" > temp_remaining.txt 2>&1
set "REMAINING=0"
for /f %%i in ('type temp_remaining.txt ^| find /C /V ""') do set "REMAINING=%%i"
if !REMAINING! EQU 0 (
    call :log_success "All containers stopped"
) else (
    call :log_warning "!REMAINING! container(s) still running:"
    for /f "tokens=*" %%l in (temp_remaining.txt) do call :log_warning "  %%l"
)
del temp_remaining.txt 2>nul

REM ============================================================================
REM PHASE 3: Git Branch Switch
REM ============================================================================
call :header "PHASE 3 - Git Branch Switch"

call :log "[Fetching latest remote refs]"
git fetch origin
if errorlevel 1 (
    call :log_warning "git fetch failed (no internet?) - continuing with local refs"
) else (
    call :log_success "git fetch complete"
)

call :log ""
call :log "[Stashing any local changes]"
git stash push -m "pre-switch-to-release-aws_%TS% (auto-stash by switch_to_release_aws.bat)"
if errorlevel 1 (
    call :log_info "Nothing to stash (working tree clean)"
) else (
    call :log_success "Local changes stashed - restore later with: git stash pop"
)

call :log ""
call :log "[Switching to release/aws]"
git checkout release/aws
if errorlevel 1 (
    call :log_error "Failed to checkout release/aws - check git status and try manually"
    call :log_error "To restore: git checkout !CURRENT_BRANCH!"
    set /a ERRORS+=1
    goto :phase3_fail
)
call :log_success "Switched to release/aws"

call :log ""
call :log "[Pulling latest release/aws]"
git pull origin release/aws
if errorlevel 1 (
    call :log_warning "git pull failed (may be up to date or no internet)"
) else (
    call :log_success "Branch is up to date"
)

for /f "tokens=*" %%b in ('git branch --show-current 2^>^&1') do (
    call :log_info "Current branch is now: %%b"
)
goto :phase3_done

:phase3_fail
echo.
echo Phase 3 FAILED. To rollback manually:
echo   git checkout !CURRENT_BRANCH!
echo   cd [service] ^&^& docker compose up -d
echo.
goto :abort

:phase3_done

REM ============================================================================
REM PHASE 4: Patch .env Files (LOCAL mode adjustments)
REM ============================================================================
call :header "PHASE 4 - Patch .env Files for Local Run"
call :log "Goal: keep databases/email pointing to local Docker containers"
call :log "      even though release/aws may reference AWS endpoints."
call :log ""

REM ---- Detect and report new keys in .env.example after branch checkout ----
call :log "[Checking for NEW keys in .env.example files (added in release/aws)]"
call :log ""
set "NEW_KEYS_FOUND=0"

for %%s in (auth-service accounting-service flowise-proxy-service-py bridge flowise) do (
    if exist "%%s\.env.example" (
        if exist "%%s\.env" (
            call :log "  [%%s]"
            for /f "eol=# tokens=1 delims==" %%k in ('findstr /v "^#" "%%s\.env.example" 2^>nul ^| findstr /v "^$"') do (
                if not "%%k"=="" (
                    findstr /B /C:"%%k=" "%%s\.env" >nul 2>&1
                    if errorlevel 1 (
                        call :log_warning "    NEW (not in .env): %%k"
                        set /a NEW_KEYS_FOUND+=1
                    )
                )
            )
        )
    )
)

if !NEW_KEYS_FOUND! GTR 0 (
    call :log ""
    call :log_warning "!NEW_KEYS_FOUND! new key(s) found that need values."
    call :log_warning "The .env.example files show the required format."
    call :log_warning "Default safe values will be kept (no AWS endpoints injected)."
)

REM ---- Local-mode guardrails: ensure NODE_ENV=production is safe locally ----
call :log ""
call :log "[Verifying local-safety of critical vars]"
call :log "  (Databases, SMTP, CORS kept as localhost - not switched to AWS)"
call :log ""

REM auth-service: ensure CORS still has localhost, SMTP stays mailhog
if exist "auth-service\.env" (
    findstr /C:"CORS_ORIGIN=https://" "auth-service\.env" >nul 2>&1
    if not errorlevel 1 (
        call :log_warning "auth-service CORS_ORIGIN appears to be an https:// URL."
        call :log_warning "For local run, ensure it includes http://localhost:3082"
        call :log_warning "Current value:"
        for /f "tokens=2 delims==" %%v in ('findstr /B /C:"CORS_ORIGIN=" auth-service\.env 2^>nul') do call :log_warning "  CORS_ORIGIN=%%v"
    ) else (
        call :log_success "auth-service CORS_ORIGIN looks local (OK)"
    )

    findstr /C:"SMTP_HOST=email-smtp" "auth-service\.env" >nul 2>&1
    if not errorlevel 1 (
        call :log_error "auth-service SMTP_HOST points to AWS SES - NOT usable locally without credentials"
        call :log_error "Fix: Edit auth-service\.env and set SMTP_HOST=mailhog"
        set /a ERRORS+=1
    ) else (
        call :log_success "auth-service SMTP_HOST is not AWS SES (OK for local)"
    )
)

REM flowise-proxy: ensure FLOWISE_API_URL and auth URL are still localhost/container names
if exist "flowise-proxy-service-py\.env" (
    findstr /C:"FLOWISE_API_URL=https://" "flowise-proxy-service-py\.env" >nul 2>&1
    if not errorlevel 1 (
        call :log_error "flowise-proxy FLOWISE_API_URL points to HTTPS - must be http://flowise:3002 for local run"
        set /a ERRORS+=1
    ) else (
        call :log_success "flowise-proxy FLOWISE_API_URL looks local (OK)"
    )

    findstr /C:"EXTERNAL_AUTH_URL=https://" "flowise-proxy-service-py\.env" >nul 2>&1
    if not errorlevel 1 (
        call :log_error "flowise-proxy EXTERNAL_AUTH_URL points to HTTPS - must be http://auth-service:3000 for local"
        set /a ERRORS+=1
    ) else (
        call :log_success "flowise-proxy EXTERNAL_AUTH_URL looks local (OK)"
    )
)

REM accounting-service: DB check
if exist "accounting-service\.env" (
    findstr /C:"DB_HOST=localhost\|DB_HOST=postgres" "accounting-service\.env" >nul 2>&1
    if not errorlevel 1 (
        call :log_success "accounting-service DB_HOST looks local (OK)"
    ) else (
        call :log_warning "accounting-service DB_HOST may be unexpected - review accounting-service\.env"
    )
)

if !ERRORS! GTR 0 (
    echo.
    call :log_error "!ERRORS! local-safety error(s) found in Phase 4."
    call :log_error "Edit the .env files listed above to fix, then re-run this script."
    echo.
    echo Press any key to open the backup dir for reference...
    pause >nul
    explorer "%BACKUP_DIR%"
    goto :abort
)

call :log_success "All critical .env local-safety checks passed"

REM ============================================================================
REM PHASE 5: Rebuild Docker Images
REM ============================================================================
call :header "PHASE 5 - Rebuild Docker Images"
call :log "Building with --no-cache to get fresh images from release/aws code."
call :log ""

echo.
set /p "BUILDIT=Rebuild all Docker images now? This may take 5-15 min. (y/N): "
if /i not "!BUILDIT!"=="y" (
    call :log_warning "Skipped rebuild - using existing images (may be stale)"
    goto :phase5_done
)

REM auth-service: uses docker-compose.dev.yml with Dockerfile.prod if present
call :log "[Building auth-service]"
if exist "auth-service\Dockerfile.prod" (
    call :log_info "  Using Dockerfile.prod (production multi-stage build)"
    docker build -f auth-service/Dockerfile.prod -t auth-service:local auth-service
) else (
    call :log_info "  Using Dockerfile (dev build)"
    pushd auth-service
    docker compose -f docker-compose.dev.yml build --no-cache
    popd
)
if errorlevel 1 (
    call :log_error "auth-service build FAILED"
    set /a ERRORS+=1
) else (
    call :log_success "auth-service build OK"
)

REM accounting-service
call :log ""
call :log "[Building accounting-service]"
pushd accounting-service
docker compose build --no-cache
popd
if errorlevel 1 (
    call :log_error "accounting-service build FAILED"
    set /a ERRORS+=1
) else (
    call :log_success "accounting-service build OK"
)

REM flowise-proxy-service-py
call :log ""
call :log "[Building flowise-proxy-service-py]"
pushd flowise-proxy-service-py
docker compose build --no-cache
popd
if errorlevel 1 (
    call :log_error "flowise-proxy-service-py build FAILED"
    set /a ERRORS+=1
) else (
    call :log_success "flowise-proxy-service-py build OK"
)

REM bridge
call :log ""
call :log "[Building bridge]"
if exist "bridge\docker-compose.yml" (
    pushd bridge
    docker compose build --no-cache
    popd
) else (
    docker build -t bridge:local bridge
)
if errorlevel 1 (
    call :log_error "bridge build FAILED"
    set /a ERRORS+=1
) else (
    call :log_success "bridge build OK"
)

if !ERRORS! GTR 0 (
    call :log_error "!ERRORS! build(s) failed. Review output above."
    echo.
    set /p "CONT_ANYWAY=Continue to Phase 6 anyway? (y/N): "
    if /i not "!CONT_ANYWAY!"=="y" goto :abort
)

:phase5_done

REM ============================================================================
REM PHASE 6: Start Services + Verify Health
REM ============================================================================
call :header "PHASE 6 - Start Services"
call :log "Starting in dependency order: flowise -> auth -> accounting -> proxy -> bridge"
call :log ""

REM flowise (includes its own postgres)
call :log "[Starting flowise]"
if exist "flowise\docker-compose.yml" (
    pushd flowise
    docker compose up -d
    popd
    if errorlevel 1 (
        call :log_error "flowise failed to start"
        set /a ERRORS+=1
    ) else (
        call :log_success "flowise started"
    )
)

REM auth-service
call :log ""
call :log "[Starting auth-service]"
if exist "auth-service\docker-compose.dev.yml" (
    pushd auth-service
    docker compose -f docker-compose.dev.yml up -d
    popd
    if errorlevel 1 (
        call :log_error "auth-service failed to start"
        set /a ERRORS+=1
    ) else (
        call :log_success "auth-service started"
    )
) else if exist "auth-service\docker-compose.prod.yml" (
    call :log_info "Using docker-compose.prod.yml (found in release/aws branch)"
    pushd auth-service
    docker compose -f docker-compose.prod.yml up -d
    popd
)

REM accounting-service
call :log ""
call :log "[Starting accounting-service]"
if exist "accounting-service\docker-compose.yml" (
    pushd accounting-service
    docker compose up -d
    popd
    if errorlevel 1 (
        call :log_error "accounting-service failed to start"
        set /a ERRORS+=1
    ) else (
        call :log_success "accounting-service started"
    )
)

REM flowise-proxy-service-py
call :log ""
call :log "[Starting flowise-proxy-service-py]"
if exist "flowise-proxy-service-py\docker-compose.yml" (
    pushd flowise-proxy-service-py
    docker compose up -d
    popd
    if errorlevel 1 (
        call :log_error "flowise-proxy failed to start"
        set /a ERRORS+=1
    ) else (
        call :log_success "flowise-proxy started"
    )
)

REM bridge
call :log ""
call :log "[Starting bridge]"
if exist "bridge\docker-compose.yml" (
    pushd bridge
    docker compose up -d
    popd
    if errorlevel 1 (
        call :log_error "bridge failed to start"
        set /a ERRORS+=1
    ) else (
        call :log_success "bridge started"
    )
)

REM Wait for services to initialize
call :log ""
call :log "[Waiting 20 seconds for services to initialize...]"
timeout /t 20 /nobreak >nul

REM ============================================================================
REM PHASE 6 (cont.): Health Verification
REM ============================================================================
call :header "PHASE 6 (cont.) - Health Verification"

call :check_endpoint "Auth Service"       "http://localhost:3000/health"
call :check_endpoint "Accounting Service" "http://localhost:3001/health"
call :check_endpoint "Flowise Proxy"      "http://localhost:8000/health"
call :check_endpoint "Flowise"            "http://localhost:3002"
call :check_endpoint "Bridge UI"          "http://localhost:3082"

call :log ""
call :log "[All running containers]"
docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}" > temp_final_ps.txt 2>&1
for /f "tokens=*" %%l in (temp_final_ps.txt) do call :log_info "%%l"
del temp_final_ps.txt 2>nul

REM ============================================================================
REM FINAL SUMMARY
REM ============================================================================
call :header "MIGRATION SUMMARY"

set "FINAL_ERRORS=0"
set "FINAL_WARNINGS=0"
for /f %%i in ('findstr /C:"[ERROR]" "%OUTPUT_FILE%" 2^>nul ^| find /C "[ERROR]"') do set "FINAL_ERRORS=%%i"
for /f %%i in ('findstr /C:"[WARN]" "%OUTPUT_FILE%" 2^>nul ^| find /C "[WARN]"') do set "FINAL_WARNINGS=%%i"

for /f "tokens=*" %%b in ('git branch --show-current 2^>^&1') do set "FINAL_BRANCH=%%b"

call :log ""
call :log "Branch:   !FINAL_BRANCH!"
call :log "Errors:   !FINAL_ERRORS!"
call :log "Warnings: !FINAL_WARNINGS!"
call :log ""

if !FINAL_ERRORS! EQU 0 (
    call :log_success "Migration COMPLETE - services running on release/aws (local mode)"
    call :log ""
    call :log "Access points:"
    call :log "  Bridge UI:         http://localhost:3082"
    call :log "  Auth API:          http://localhost:3000"
    call :log "  Accounting API:    http://localhost:3001"
    call :log "  Flowise Proxy:     http://localhost:8000"
    call :log "  Flowise:           http://localhost:3002"
    call :log ""
    call :log "To verify further, run: scan_target.bat"
    call :log ""
    call :log "To roll back to main branch:"
    call :log "  1. Stop services: run each service's stop.bat"
    call :log "  2. git checkout main"
    call :log "  3. Restore .env from backup: %BACKUP_DIR%\"
    call :log "  4. Rebuild and start services"
) else (
    call :log_error "Migration completed with !FINAL_ERRORS! error(s)."
    call :log_error "Check log: %OUTPUT_FILE%"
    call :log ""
    call :log "To roll back to main branch:"
    call :log "  git checkout main"
    call :log "  Restore .env files from: %BACKUP_DIR%\"
)

call :log ""
call :log "=========================================="
call :log "End of switch_to_release_aws log"
call :log "=========================================="

echo.
echo ════════════════════════════════════════════════════════════════════════
echo  Done. Log: %OUTPUT_FILE%
echo  Errors: %FINAL_ERRORS%   Warnings: %FINAL_WARNINGS%
echo ════════════════════════════════════════════════════════════════════════
echo.
pause
exit /b %FINAL_ERRORS%

:abort
echo.
echo [31m[ABORTED][0m Script aborted. No destructive changes made beyond Phase 2 backup.
echo If containers were stopped and you need to restart on main:
echo   1. git checkout main (if branch was changed)
echo   2. cd [service] ^&^& docker compose up -d
echo   3. Restore .env from: %BACKUP_DIR%\
echo.
pause
exit /b 1

REM ============================================================================
REM Helper Functions
REM ============================================================================

:header
call :log ""
call :log "=========================================="
call :log "%~1"
call :log "=========================================="
call :log ""
echo.
echo [96m[%~1][0m
echo.
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
curl -s -o nul -w "%%{http_code}" "%_URL%" --max-time 8 > temp_ep.txt 2>&1
set /p _STATUS=<temp_ep.txt
del temp_ep.txt 2>nul
if "%_STATUS%"=="200" (
    call :log_success "%_SVC%: [200 OK] %_URL%"
) else if "%_STATUS%"=="000" (
    call :log_error "%_SVC%: [NOT REACHABLE] %_URL%"
    set /a ERRORS+=1
) else (
    call :log_warning "%_SVC%: [HTTP %_STATUS%] %_URL%"
)
goto :eof
