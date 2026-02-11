@echo off
REM ============================================================================
REM ChatProxy Platform - Setup Diagnostics Tool
REM Author: Enoch Sit
REM License: MIT
REM ============================================================================
REM This script diagnoses the setup status at each step according to SETUP_GUIDE.md
REM Useful for debugging installation issues and providing context to support agents

setlocal enabledelayedexpansion

title ChatProxy Platform - Setup Diagnostics

echo.
echo ╔════════════════════════════════════════════════════════════════════════╗
echo ║            ChatProxy Platform - Setup Diagnostics                      ║
echo ║            Analyzing system status and configuration...                ║
echo ╚════════════════════════════════════════════════════════════════════════╝
echo.

REM Output file
set "OUTPUT_FILE=setup_diagnostics_%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%.log"
set "OUTPUT_FILE=%OUTPUT_FILE: =0%"

echo [INFO] Diagnostic report will be saved to: %OUTPUT_FILE%
echo.

REM Start logging
call :log "=========================================="
call :log "ChatProxy Platform - Setup Diagnostics"
call :log "Generated: %date% %time%"
call :log "=========================================="
call :log ""

REM ============================================================================
REM STEP 0: Prerequisites Check
REM ============================================================================
call :log "=========================================="
call :log "STEP 0: Prerequisites Check"
call :log "=========================================="

call :log ""
call :log "[Checking Docker...]"
docker --version >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker is NOT installed or not in PATH"
) else (
    for /f "tokens=*" %%i in ('docker --version 2^>^&1') do call :log_success "%%i"
)

call :log ""
call :log "[Checking Python...]"
python --version >nul 2>&1
if errorlevel 1 (
    call :log_warning "Python is NOT installed or not in PATH"
) else (
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do call :log_success "%%i"
)

call :log ""
call :log "[Checking Docker Compose...]"
docker compose version >nul 2>&1
if errorlevel 1 (
    call :log_error "Docker Compose is NOT available"
) else (
    for /f "tokens=*" %%i in ('docker compose version 2^>^&1') do call :log_success "%%i"
)

REM ============================================================================
REM STEP 1: Environment Files Check
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 1: Environment Files Check"
call :log "=========================================="

set "SERVICES=flowise auth-service accounting-service flowise-proxy-service-py bridge"

for %%s in (%SERVICES%) do (
    call :log ""
    call :log "[Checking %%s/.env...]"
    if exist "%%s\.env" (
        call :log_success "%%s/.env EXISTS"
        
        REM Check file size
        for %%f in ("%%s\.env") do (
            if %%~zf LSS 100 (
                call :log_warning "%%s/.env is suspiciously small (%%~zf bytes)"
            ) else (
                call :log_info "%%s/.env size: %%~zf bytes"
            )
        )
    ) else (
        call :log_error "%%s/.env NOT FOUND - Run setup_env_files.bat first"
    )
)

REM ============================================================================
REM STEP 2: JWT Secrets Synchronization Check
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 2: JWT Secrets Synchronization"
call :log "=========================================="

call :log ""
call :log "[Checking JWT_ACCESS_SECRET in .env files...]"

if exist "auth-service\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" auth-service\.env 2^>nul') do set "JWT_AUTH=%%a"
) else (
    set "JWT_AUTH=FILE_NOT_FOUND"
)

if exist "accounting-service\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" accounting-service\.env 2^>nul') do set "JWT_ACC=%%a"
) else (
    set "JWT_ACC=FILE_NOT_FOUND"
)

if exist "flowise-proxy-service-py\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"JWT_ACCESS_SECRET=" flowise-proxy-service-py\.env 2^>nul') do set "JWT_PROXY=%%a"
) else (
    set "JWT_PROXY=FILE_NOT_FOUND"
)

call :log_info "auth-service:         !JWT_AUTH!"
call :log_info "accounting-service:   !JWT_ACC!"
call :log_info "flowise-proxy:        !JWT_PROXY!"

if "!JWT_AUTH!"=="!JWT_ACC!" if "!JWT_ACC!"=="!JWT_PROXY!" (
    call :log_success "JWT secrets MATCH across all services"
) else (
    call :log_error "JWT secrets DO NOT MATCH - Run generate_secrets.bat"
)

REM ============================================================================
REM STEP 3: Docker Containers Status
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 3: Docker Containers Status"
call :log "=========================================="

call :log ""
call :log "[Listing all containers...]"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" > temp_docker.txt 2>&1
for /f "skip=1 tokens=*" %%i in (temp_docker.txt) do call :log_info "%%i"
del temp_docker.txt 2>nul

call :log ""
call :log "[Checking critical containers...]"
set "CONTAINERS=flowise flowise-postgres auth-service mongodb-auth accounting-service postgres-accounting flowise-proxy mongodb-proxy bridge-ui"

for %%c in (%CONTAINERS%) do (
    docker ps --filter "name=%%c" --format "{{.Status}}" | findstr /C:"Up" >nul 2>&1
    if errorlevel 1 (
        call :log_error "%%c: NOT RUNNING or DOESN'T EXIST"
    ) else (
        for /f "tokens=*" %%s in ('docker ps --filter "name=%%c" --format "{{.Status}}" 2^>^&1') do (
            echo %%s | findstr /C:"healthy" >nul 2>&1
            if errorlevel 1 (
                call :log_warning "%%c: %%s"
            ) else (
                call :log_success "%%c: %%s"
            )
        )
    )
)

REM ============================================================================
REM STEP 4: JWT Secrets in Running Containers
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 4: JWT Secrets in Running Containers"
call :log "=========================================="

call :log ""
call :log "[Checking JWT_ACCESS_SECRET in running containers...]"

docker ps --filter "name=auth-service" --format "{{.Names}}" | findstr /C:"auth-service" >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=2 delims==" %%a in ('docker exec auth-service printenv 2^>nul ^| findstr /C:"JWT_ACCESS_SECRET="') do (
        call :log_info "auth-service (container): %%a"
        set "JWT_AUTH_CONTAINER=%%a"
    )
) else (
    call :log_warning "auth-service container not running"
    set "JWT_AUTH_CONTAINER=NOT_RUNNING"
)

docker ps --filter "name=flowise-proxy" --format "{{.Names}}" | findstr /C:"flowise-proxy" >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=2 delims==" %%a in ('docker exec flowise-proxy printenv 2^>nul ^| findstr /C:"JWT_ACCESS_SECRET="') do (
        call :log_info "flowise-proxy (container): %%a"
        set "JWT_PROXY_CONTAINER=%%a"
    )
) else (
    call :log_warning "flowise-proxy container not running"
    set "JWT_PROXY_CONTAINER=NOT_RUNNING"
)

call :log ""
if "!JWT_AUTH_CONTAINER!"=="!JWT_PROXY_CONTAINER!" (
    call :log_success "Container JWT secrets MATCH"
) else (
    call :log_error "Container JWT secrets DO NOT MATCH - Restart services"
)

REM ============================================================================
REM STEP 5: Database Passwords Check
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 5: Database Passwords Check"
call :log "=========================================="

call :log ""
call :log "[Checking PostgreSQL passwords...]"

if exist "flowise\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"POSTGRES_PASSWORD=" flowise\.env 2^>nul') do (
        call :log_info "flowise/.env POSTGRES_PASSWORD: %%a"
        echo %%a | findstr /C:"$" >nul 2>&1
        if not errorlevel 1 call :log_error "PASSWORD CONTAINS $ - This breaks Docker Compose!"
    )
) else (
    call :log_error "flowise/.env not found"
)

if exist "accounting-service\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"POSTGRES_PASSWORD=" accounting-service\.env 2^>nul') do (
        call :log_info "accounting-service/.env POSTGRES_PASSWORD: %%a"
        echo %%a | findstr /C:"$" >nul 2>&1
        if not errorlevel 1 call :log_error "PASSWORD CONTAINS $ - This breaks Docker Compose!"
    )
) else (
    call :log_error "accounting-service/.env not found"
)

call :log ""
call :log "[Checking MongoDB passwords...]"

if exist "auth-service\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"MONGO_INITDB_ROOT_PASSWORD=" auth-service\.env 2^>nul') do (
        call :log_info "auth-service/.env MONGO_PASSWORD: %%a"
        echo %%a | findstr /C:"$" >nul 2>&1
        if not errorlevel 1 call :log_error "PASSWORD CONTAINS $ - This breaks Docker Compose!"
    )
) else (
    call :log_error "auth-service/.env not found"
)

REM ============================================================================
REM STEP 6: Flowise API Key Check
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 6: Flowise API Key Configuration"
call :log "=========================================="

call :log ""
call :log "[Checking Flowise API key...]"

if exist "flowise-proxy-service-py\.env" (
    for /f "tokens=2 delims==" %%a in ('findstr /C:"FLOWISE_API_KEY=" flowise-proxy-service-py\.env 2^>nul') do (
        set "API_KEY=%%a"
    )
    
    if "!API_KEY!"=="" (
        call :log_error "FLOWISE_API_KEY is EMPTY - Run configure_flowise_api.bat"
    ) else (
        if "!API_KEY!"=="your-flowise-api-key-here" (
            call :log_error "FLOWISE_API_KEY is PLACEHOLDER - Run configure_flowise_api.bat"
        ) else (
            call :log_success "FLOWISE_API_KEY is SET: !API_KEY!"
        )
    )
) else (
    call :log_error "flowise-proxy-service-py/.env not found"
)

REM ============================================================================
REM STEP 7: Service Endpoints Check
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 7: Service Endpoints Availability"
call :log "=========================================="

call :log ""
call :log "[Testing HTTP endpoints...]"

call :check_endpoint "Flowise" "http://localhost:3002"
call :check_endpoint "Auth Service" "http://localhost:3000/health"
call :check_endpoint "Accounting Service" "http://localhost:3001/health"
call :check_endpoint "Flowise Proxy" "http://localhost:8000/health"
call :check_endpoint "Bridge UI" "http://localhost:3082"

REM ============================================================================
REM STEP 8: Recent Container Logs Analysis
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 8: Recent Container Logs (Errors)"
call :log "=========================================="

for %%c in (flowise auth-service accounting-service flowise-proxy) do (
    call :log ""
    call :log "[%%c recent errors...]"
    docker ps --filter "name=%%c" --format "{{.Names}}" | findstr /C:"%%c" >nul 2>&1
    if not errorlevel 1 (
        docker logs %%c --tail=20 2>&1 | findstr /I /C:"error" /C:"fail" /C:"401" /C:"authentication" /C:"cannot" 2>nul > temp_log.txt
        if exist temp_log.txt (
            for /f "tokens=*" %%l in (temp_log.txt) do call :log_warning "  %%l"
            del temp_log.txt 2>nul
        )
    ) else (
        call :log_warning "%%c not running - cannot check logs"
    )
)

REM ============================================================================
REM STEP 9: Docker Networks Check
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 9: Docker Networks"
call :log "=========================================="

call :log ""
call :log "[Checking chatproxy-network...]"
docker network ls | findstr /C:"chatproxy-network" >nul 2>&1
if errorlevel 1 (
    call :log_error "chatproxy-network NOT FOUND - Services cannot communicate"
) else (
    call :log_success "chatproxy-network EXISTS"
    docker network inspect chatproxy-network --format "{{range .Containers}}{{.Name}} {{end}}" 2>nul > temp_network.txt
    call :log_info "Connected containers:"
    for /f "tokens=*" %%i in (temp_network.txt) do call :log_info "  %%i"
    del temp_network.txt 2>nul
)

REM ============================================================================
REM STEP 10: Summary and Recommendations
REM ============================================================================
call :log ""
call :log "=========================================="
call :log "STEP 10: Summary and Recommendations"
call :log "=========================================="
call :log ""

REM Count issues
set "ERROR_COUNT=0"
set "WARNING_COUNT=0"
findstr /C:"[ERROR]" "%OUTPUT_FILE%" >nul 2>&1
if not errorlevel 1 (
    for /f %%i in ('findstr /C:"[ERROR]" "%OUTPUT_FILE%" 2^>nul ^| find /C "[ERROR]"') do set "ERROR_COUNT=%%i"
)
findstr /C:"[WARNING]" "%OUTPUT_FILE%" >nul 2>&1
if not errorlevel 1 (
    for /f %%i in ('findstr /C:"[WARNING]" "%OUTPUT_FILE%" 2^>nul ^| find /C "[WARNING]"') do set "WARNING_COUNT=%%i"
)

call :log "Diagnostic scan complete!"
call :log ""
call :log "Found !ERROR_COUNT! errors and !WARNING_COUNT! warnings"
call :log ""

if !ERROR_COUNT! GTR 0 (
    call :log "RECOMMENDED ACTIONS:"
    call :log ""
    
    findstr /C:"JWT secrets DO NOT MATCH" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 (
        call :log "1. Run: generate_secrets.bat"
        call :log "   Then restart all services"
    )
    
    findstr /C:"PASSWORD CONTAINS $" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 (
        call :log "2. Passwords contain shell-special characters ($, &, %%)"
        call :log "   Run: generate_secrets.bat (using updated script)"
        call :log "   Then: docker compose down -v (WARNING: Deletes data!)"
        call :log "   Then: docker compose up -d"
    )
    
    findstr /C:"FLOWISE_API_KEY is EMPTY\|FLOWISE_API_KEY is PLACEHOLDER" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 (
        call :log "3. Configure Flowise API key"
        call :log "   Run: configure_flowise_api.bat"
    )
    
    findstr /C:"NOT RUNNING" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 (
        call :log "4. Start missing services:"
        call :log "   cd [service-dir]"
        call :log "   docker compose up -d"
    )
    
    findstr /C:"Container JWT secrets DO NOT MATCH" "%OUTPUT_FILE%" >nul 2>&1
    if not errorlevel 1 (
        call :log "5. Restart services to reload environment:"
        call :log "   cd auth-service && docker compose -f docker-compose.dev.yml down && docker compose -f docker-compose.dev.yml up -d"
        call :log "   cd flowise-proxy-service-py && docker compose down && docker compose up -d"
    )
) else (
    call :log_success "All checks passed! System appears to be configured correctly."
)

call :log ""
call :log "=========================================="
call :log "End of Diagnostics Report"
call :log "=========================================="

echo.
echo ════════════════════════════════════════════════════════════════════════
echo [SUCCESS] Diagnostics complete!
echo ════════════════════════════════════════════════════════════════════════
echo.
echo Full report saved to: %OUTPUT_FILE%
echo.
echo Found %ERROR_COUNT% errors and %WARNING_COUNT% warnings
echo.
if %ERROR_COUNT% GTR 0 (
    echo [ERROR] Issues detected - See recommendations in the report
    echo.
    echo To view the full report:
    echo   notepad %OUTPUT_FILE%
    echo.
) else (
    echo [SUCCESS] No critical issues detected!
)

pause
exit /b 0

REM ============================================================================
REM Helper Functions
REM ============================================================================

:log
echo %~1
echo %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_success
echo [32m[SUCCESS][0m %~1
echo [SUCCESS] %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_error
echo [31m[ERROR][0m %~1
echo [ERROR] %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_warning
echo [33m[WARNING][0m %~1
echo [WARNING] %~1 >> "%OUTPUT_FILE%"
goto :eof

:log_info
echo [36m[INFO][0m %~1
echo [INFO] %~1 >> "%OUTPUT_FILE%"
goto :eof

:check_endpoint
set "SERVICE_NAME=%~1"
set "URL=%~2"
curl -s -o nul -w "%%{http_code}" "%URL%" --max-time 3 > temp_status.txt 2>&1
set /p STATUS=<temp_status.txt
del temp_status.txt 2>nul

if "%STATUS%"=="200" (
    call :log_success "%SERVICE_NAME%: %URL% - HTTP 200 OK"
) else if "%STATUS%"=="000" (
    call :log_error "%SERVICE_NAME%: %URL% - NOT REACHABLE"
) else (
    call :log_warning "%SERVICE_NAME%: %URL% - HTTP %STATUS%"
)
goto :eof
