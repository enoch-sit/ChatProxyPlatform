@echo off
echo ========================================
echo Starting Flowise with PostgreSQL
echo ========================================
echo.

REM Verify .env file exists
if not exist .env (
    echo [ERROR] .env file not found!
    echo Please ensure .env file exists in the flowise directory
    pause
    exit /b 1
)

REM Start services with explicit --env-file flag
docker compose --env-file .env up -d

echo.
echo ========================================
echo Flowise is starting with PostgreSQL...
echo Access at: http://localhost:3002
echo PostgreSQL Port: 5433
echo ========================================
echo.
echo To view logs: docker logs flowise -f
echo To stop: docker compose down
echo.
