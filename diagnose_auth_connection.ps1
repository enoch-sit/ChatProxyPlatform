# =============================================================================
# diagnose_auth_connection.ps1
# Diagnoses: "Cannot connect to auth service at http://auth-service:3000"
#
# Run on target machine (PowerShell):
#   powershell -ExecutionPolicy Bypass -File diagnose_auth_connection.ps1
# =============================================================================

function Write-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }

Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host "  AUTH CONNECTION DIAGNOSTIC" -ForegroundColor White
Write-Host "  $(Get-Date)" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White

# --------------------------------------------------------------------------
# 1. Check containers are running
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 1. Container Status ---"

$allContainers = docker ps --format "{{.Names}}:{{.Status}}" 2>&1

$authRunning  = $allContainers | Where-Object { $_ -match "^auth-service:" }
$proxyRunning = $allContainers | Where-Object { $_ -match "^flowise-proxy:" }

if ($authRunning) {
    Write-Ok "auth-service is running: $authRunning"
} else {
    Write-Fail "auth-service container is NOT running"
    Write-Info "All running containers:"
    docker ps --format "  {{.Names}}`t{{.Status}}" 2>&1
}

if ($proxyRunning) {
    Write-Ok "flowise-proxy is running: $proxyRunning"
} else {
    Write-Fail "flowise-proxy container is NOT running"
}

# --------------------------------------------------------------------------
# 2. Check chatproxy-network exists
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 2. chatproxy-network ---"

$networkExists = docker network inspect chatproxy-network 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Ok "chatproxy-network exists"
} else {
    Write-Fail "chatproxy-network does NOT exist"
    Write-Info "Available networks:"
    docker network ls --format "  {{.Name}}" 2>&1
    Write-Host ""
    Write-Warn "FIX: Create the shared network, then restart both services:"
    Write-Host "       docker network create chatproxy-network"
    Write-Host "       cd auth-service            ; docker compose -f docker-compose.dev.yml up -d"
    Write-Host "       cd flowise-proxy-service-py ; docker compose up -d"
}

# --------------------------------------------------------------------------
# 3. Check both containers are on chatproxy-network
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 3. Containers connected to chatproxy-network ---"

$networkMembers = docker network inspect chatproxy-network --format "{{range .Containers}}{{.Name}} {{end}}" 2>&1
Write-Info "Members on chatproxy-network: $networkMembers"

if ($networkMembers -match "auth-service") {
    Write-Ok "auth-service IS on chatproxy-network"
} else {
    Write-Fail "auth-service is NOT on chatproxy-network"
    Write-Warn "FIX: docker network connect chatproxy-network auth-service"
}

if ($networkMembers -match "flowise-proxy") {
    Write-Ok "flowise-proxy IS on chatproxy-network"
} else {
    Write-Fail "flowise-proxy is NOT on chatproxy-network"
    Write-Warn "FIX: docker network connect chatproxy-network flowise-proxy"
}

# --------------------------------------------------------------------------
# 4. Check EXTERNAL_AUTH_URL inside flowise-proxy
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 4. EXTERNAL_AUTH_URL inside flowise-proxy ---"

$extAuthUrl = docker exec flowise-proxy printenv EXTERNAL_AUTH_URL 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($extAuthUrl)) {
    Write-Fail "EXTERNAL_AUTH_URL is not set inside flowise-proxy container"
} else {
    Write-Ok "EXTERNAL_AUTH_URL = $extAuthUrl"
    if ($extAuthUrl.Trim() -eq "http://auth-service:3000") {
        Write-Ok "URL format is correct"
    } else {
        Write-Warn "Expected http://auth-service:3000 but got: $extAuthUrl"
    }
}

# --------------------------------------------------------------------------
# 5. DNS resolution: can flowise-proxy resolve 'auth-service'?
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 5. DNS resolution inside flowise-proxy ---"

$dnsResult = docker exec flowise-proxy getent hosts auth-service 2>&1
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($dnsResult)) {
    Write-Ok "auth-service resolves to: $dnsResult"
} else {
    # Try nslookup as fallback (available in most images)
    $nsResult = docker exec flowise-proxy nslookup auth-service 2>&1
    if ($nsResult -match "Address") {
        Write-Ok "auth-service DNS lookup succeeded (nslookup):"
        Write-Info $nsResult
    } else {
        Write-Fail "flowise-proxy cannot resolve hostname 'auth-service'"
        Write-Info "getent output : $dnsResult"
        Write-Info "nslookup output: $nsResult"
        Write-Warn "Root cause: containers are not on the same Docker network"
    }
}

# --------------------------------------------------------------------------
# 6. TCP connectivity: can flowise-proxy reach auth-service:3000?
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 6. TCP connectivity flowise-proxy -> auth-service:3000 ---"

$httpCode = docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://auth-service:3000/ 2>&1
if ($httpCode -and $httpCode -ne "000") {
    Write-Ok "TCP connection succeeded (HTTP $httpCode from /)"
} else {
    Write-Fail "TCP connection to auth-service:3000 failed (HTTP code: '$httpCode')"
    # Fallback: try nc if available
    $ncResult = docker exec flowise-proxy sh -c "nc -zv auth-service 3000 2>&1" 2>&1
    Write-Info "nc result: $ncResult"
}

# --------------------------------------------------------------------------
# 7. Check the login endpoint specifically
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 7. POST /api/auth/login endpoint ---"

$loginCode = docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" `
    --max-time 5 `
    -X POST http://auth-service:3000/api/auth/login `
    -H "Content-Type: application/json" `
    -d '{"username":"_diagnostic_probe_","password":"_probe_"}' 2>&1

switch ($loginCode) {
    { $_ -in "400","401","422" } {
        Write-Ok "Login endpoint reachable (HTTP $loginCode - wrong credentials but server is UP)"
    }
    "200" {
        Write-Ok "Login endpoint reachable and returned 200"
    }
    "404" {
        Write-Fail "Login endpoint returned 404 ??path /api/auth/login may be wrong"
        Write-Info "Probing alternate paths..."
        $paths = @("/api/v1/auth/login", "/auth/login", "/login", "/api/login")
        foreach ($path in $paths) {
            $code = docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" `
                --max-time 5 -X POST "http://auth-service:3000$path" `
                -H "Content-Type: application/json" `
                -d '{"username":"probe","password":"probe"}' 2>&1
            Write-Info "  $path  ->  HTTP $code"
        }
    }
    { $_ -in "000","" } {
        Write-Fail "Login endpoint unreachable (connection refused or DNS failed)"
    }
    default {
        Write-Warn "Login endpoint returned HTTP $loginCode"
    }
}

# --------------------------------------------------------------------------
# 8. auth-service recent logs
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "--- 8. auth-service recent logs (last 20 lines) ---"

$authLogs = docker logs auth-service --tail=20 2>&1
if ($LASTEXITCODE -eq 0) {
    $authLogs | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Warn "Could not read auth-service logs: $authLogs"
}

# --------------------------------------------------------------------------
# 9. Summary
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor White
Write-Host "  SUMMARY / MOST COMMON FIXES" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor White
Write-Host ""
Write-Host "If DNS failed (step 5) or containers not on network (step 3):"
Write-Host "  docker network create chatproxy-network            # if needed"
Write-Host "  docker network connect chatproxy-network auth-service"
Write-Host "  docker network connect chatproxy-network flowise-proxy"
Write-Host ""
Write-Host "If auth-service is not running (step 1):"
Write-Host "  cd auth-service"
Write-Host "  docker compose -f docker-compose.dev.yml up -d"
Write-Host ""
Write-Host "If EXTERNAL_AUTH_URL is wrong (step 4):"
Write-Host "  Edit flowise-proxy-service-py\.env and set:"
Write-Host "  EXTERNAL_AUTH_URL=http://auth-service:3000"
Write-Host "  Then: cd flowise-proxy-service-py"
Write-Host "        docker compose up -d --force-recreate"
Write-Host ""
Write-Host "If the login path is wrong (step 7 returned 404):"
Write-Host "  Check auth-service routes and update EXTERNAL_AUTH_URL path accordingly"
Write-Host "============================================================" -ForegroundColor White
