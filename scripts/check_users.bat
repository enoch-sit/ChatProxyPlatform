@echo off
REM ============================================
REM Check User Status in Database
REM ============================================

setlocal enabledelayedexpansion

set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "BLUE=[94m"
set "RESET=[0m"

echo.
echo %BLUE%============================================%RESET%
echo %BLUE%  USER DATABASE STATUS%RESET%
echo %BLUE%============================================%RESET%
echo.

REM Check if Docker is running
docker ps >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] Docker is not running%RESET%
    echo Please start Docker Desktop first.
    echo.
    pause
    exit /b 1
)

REM Check if MongoDB container is running
docker ps --filter "name=mongodb-auth" --filter "status=running" | findstr "mongodb" >nul 2>&1
if %errorlevel% neq 0 (
    echo %RED%[✗] MongoDB container is not running%RESET%
    echo Please start the auth service: cd auth-service && start.bat
    echo.
    pause
    exit /b 1
)

echo Fetching user information from database...
echo.

REM Get total user count
for /f %%i in ('docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.countDocuments()"') do set "USER_COUNT=%%i"
echo Total Users: %USER_COUNT%
echo.

if "%USER_COUNT%"=="0" (
    echo %YELLOW%No users found in database.%RESET%
    echo.
    echo To create an admin user:
    echo   cd auth-service\quickCreateAdminPy
    echo   python create_admin.py
    echo.
    pause
    exit /b 0
)

echo %BLUE%User Details:%RESET%
echo ----------------------------------------

REM List all users with their status
docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.find({}, {username: 1, email: 1, isVerified: 1, role: 1, _id: 0}).forEach(u => { print('Username: ' + u.username); print('  Email: ' + u.email); print('  Role: ' + u.role); print('  Verified: ' + u.isVerified); print('') })"

echo.
echo ----------------------------------------

REM Check specifically for admin users
docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.findOne({username: 'admin'})" >nul 2>&1
if %errorlevel% equ 0 (
    docker exec mongodb-auth mongosh --quiet --eval "use auth_db; var u = db.users.findOne({username: 'admin'}); if (u.isVerified) { print('Admin user is VERIFIED'); } else { print('Admin user is NOT VERIFIED'); }"
)

docker exec mongodb-auth mongosh --quiet --eval "use auth_db; db.users.findOne({username: 'admin@admin'})" >nul 2>&1
if %errorlevel% equ 0 (
    docker exec mongodb-auth mongosh --quiet --eval "use auth_db; var u = db.users.findOne({username: 'admin@admin'}); if (u.isVerified) { print('Admin@admin user is VERIFIED'); } else { print('Admin@admin user is NOT VERIFIED'); }"
)

echo.
echo %BLUE%============================================%RESET%
echo.
echo To verify a user manually:
echo   docker exec mongodb-auth mongosh --eval "use auth_db; db.users.updateOne({username: 'USERNAME'}, {$set: {isVerified: true}})"
echo.
echo To create a new admin user:
echo   cd auth-service\quickCreateAdminPy
echo   python create_admin.py
echo.

pause
