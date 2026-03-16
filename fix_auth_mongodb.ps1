# =============================================================================
# fix_auth_mongodb.ps1
# Fixes: auth-service cannot reach mongodb-auth (EAI_AGAIN dns error)
#        which causes auth-service HTTP server to never start
#
# Run on target machine:
#   powershell -ExecutionPolicy Bypass -File fix_auth_mongodb.ps1
# =============================================================================

function Write-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Fix  { param($msg) Write-Host "[FIX]  $msg" -ForegroundColor Magenta }

Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host "  AUTH-SERVICE MONGODB FIX" -ForegroundColor White
Write-Host "  $(Get-Date)" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host "Root cause: auth-service cannot resolve 'mongodb-auth'" -ForegroundColor Yellow
Write-Host "  -> Mongoose fails to connect on startup" -ForegroundColor Yellow
Write-Host "  -> HTTP server never starts -> port 3000 refuses connections" -ForegroundColor Yellow
Write-Host ""

# --------------------------------------------------------------------------
# 1. Check mongodb-auth is running
# --------------------------------------------------------------------------
Write-Host "--- 1. Check mongodb-auth container ---"

$mongoRunning = docker ps --filter "name=mongodb-auth" --format "{{.Names}}:{{.Status}}" 2>&1
$mongoAll     = docker ps -a --filter "name=mongodb-auth" --format "{{.Names}}:{{.Status}}" 2>&1

if ($mongoRunning -match "mongodb-auth") {
    Write-Ok "mongodb-auth is running: $mongoRunning"
} elseif ($mongoAll -match "mongodb-auth") {
    Write-Fail "mongodb-auth EXISTS but is stopped: $mongoAll"
    Write-Fix "Starting mongodb-auth..."
    docker start mongodb-auth
    Start-Sleep -Seconds 5
    $mongoRunning = docker ps --filter "name=mongodb-auth" --format "{{.Names}}:{{.Status}}" 2>&1
    if ($mongoRunning -match "mongodb-auth") {
        Write-Ok "mongodb-auth started successfully"
    } else {
        Write-Fail "mongodb-auth failed to start - try: cd auth-service ; docker compose -f docker-compose.dev.yml up -d"
        exit 1
    }
} else {
    Write-Fail "mongodb-auth container does NOT exist at all"
    Write-Fix "Creating and starting via docker compose..."
    Push-Location auth-service
    docker compose -f docker-compose.dev.yml up -d mongodb
    Pop-Location
    Start-Sleep -Seconds 8
    $mongoRunning = docker ps --filter "name=mongodb-auth" --format "{{.Names}}:{{.Status}}" 2>&1
    if ($mongoRunning -match "mongodb-auth") {
        Write-Ok "mongodb-auth created and started"
    } else {
        Write-Fail "Could not create mongodb-auth. Run manually: cd auth-service ; docker compose -f docker-compose.dev.yml up -d"
        exit 1
    }
}

# --------------------------------------------------------------------------
# 2. Find which network auth-service is on
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 2. Verify network shared between auth-service and mongodb-auth ---"

$authNetworks  = (docker inspect auth-service  --format "{{json .NetworkSettings.Networks}}" 2>&1 | ConvertFrom-Json).PSObject.Properties.Name -join " "
$mongoNetworks = (docker inspect mongodb-auth --format "{{json .NetworkSettings.Networks}}" 2>&1 | ConvertFrom-Json).PSObject.Properties.Name -join " "

Write-Info "auth-service  networks: $authNetworks"
Write-Info "mongodb-auth  networks: $mongoNetworks"

# Find a common network
$authNetList  = $authNetworks  -split "\s+" | Where-Object { $_ -ne "" }
$mongoNetList = $mongoNetworks -split "\s+" | Where-Object { $_ -ne "" }
$commonNets   = $authNetList | Where-Object { $mongoNetList -contains $_ }

if ($commonNets) {
    Write-Ok "Shared network(s) found: $($commonNets -join ', ')"
} else {
    Write-Fail "auth-service and mongodb-auth share NO common network - this is why DNS fails"
    # Find the auth-service network to connect mongodb-auth to
    $authNet = $authNetList | Where-Object { $_ -match "auth" } | Select-Object -First 1
    if (-not $authNet) { $authNet = $authNetList | Select-Object -First 1 }
    Write-Fix "Connecting mongodb-auth to $authNet..."
    docker network connect $authNet mongodb-auth
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "mongodb-auth connected to $authNet"
    } else {
        Write-Fail "Failed to connect. Try: docker network connect auth-service_auth-network mongodb-auth"
    }
}

# --------------------------------------------------------------------------
# 3. Verify auth-service can now resolve mongodb-auth
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 3. DNS check: auth-service -> mongodb-auth ---"

$dnsResult = docker exec auth-service getent hosts mongodb-auth 2>&1
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($dnsResult)) {
    Write-Ok "mongodb-auth resolves to: $dnsResult"
} else {
    $nsResult = docker exec auth-service nslookup mongodb-auth 2>&1
    if ($nsResult -match "Address") {
        Write-Ok "mongodb-auth resolves (nslookup): $nsResult"
    } else {
        Write-Fail "auth-service still cannot resolve mongodb-auth"
        Write-Info "getent : $dnsResult"
        Write-Info "nslookup: $nsResult"
        Write-Warn "You may need to fully recreate auth-service via docker compose"
    }
}

# --------------------------------------------------------------------------
# 4. Restart auth-service so it reconnects to MongoDB
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 4. Restart auth-service ---"
Write-Fix "Restarting auth-service to reconnect to MongoDB..."
docker restart auth-service
if ($LASTEXITCODE -eq 0) {
    Write-Ok "auth-service restart command sent"
    Write-Info "Waiting 10 seconds for startup..."
    Start-Sleep -Seconds 10
} else {
    Write-Fail "docker restart auth-service failed"
}

# --------------------------------------------------------------------------
# 5. Verify auth-service is now listening on port 3000
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 5. Verify port 3000 is now accepting connections ---"

$httpCode = docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://auth-service:3000/ 2>&1
if ($httpCode -and $httpCode -ne "000") {
    Write-Ok "auth-service:3000 is now reachable (HTTP $httpCode)"
} else {
    Write-Warn "Still not reachable yet (HTTP $httpCode) - checking auth-service logs..."
    Write-Host ""
    Write-Host "auth-service last 30 log lines:"
    docker logs auth-service --tail=30 2>&1 | ForEach-Object { Write-Host "  $_" }
}

# --------------------------------------------------------------------------
# 6. Test the actual login endpoint
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 6. Test /api/auth/login ---"

$loginCode = docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" `
    --max-time 10 `
    -X POST http://auth-service:3000/api/auth/login `
    -H "Content-Type: application/json" `
    -d '{"username":"_probe_","password":"_probe_"}' 2>&1

if ($loginCode -in "400","401","422") {
    Write-Ok "Login endpoint responding (HTTP $loginCode - server UP, credentials just wrong)"
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  FIXED! auth-service is now reachable." -ForegroundColor Green
    Write-Host "  You can now retry your login from the bridge/UI." -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
} elseif ($loginCode -eq "000" -or [string]::IsNullOrEmpty($loginCode)) {
    Write-Fail "Login endpoint still unreachable"
    Write-Host ""
    Write-Host "Try a full recreate:" -ForegroundColor Yellow
    Write-Host "  cd auth-service"
    Write-Host "  docker compose -f docker-compose.dev.yml down"
    Write-Host "  docker compose -f docker-compose.dev.yml up -d"
} else {
    Write-Warn "Login endpoint returned HTTP $loginCode"
}
