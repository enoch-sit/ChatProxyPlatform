#!/bin/bash
# =============================================================================
# diagnose_auth_connection.sh
# Diagnoses: "Cannot connect to auth service at http://auth-service:3000"
# Run this on the TARGET machine: bash diagnose_auth_connection.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

echo ""
echo "============================================================"
echo "  AUTH CONNECTION DIAGNOSTIC"
echo "  $(date)"
echo "============================================================"

# --------------------------------------------------------------------------
# 1. Check containers are running
# --------------------------------------------------------------------------
echo ""
echo "--- 1. Container Status ---"

AUTH_RUNNING=$(docker ps --filter "name=auth-service" --format "{{.Names}}:{{.Status}}" 2>/dev/null)
PROXY_RUNNING=$(docker ps --filter "name=flowise-proxy" --format "{{.Names}}:{{.Status}}" 2>/dev/null)

if echo "$AUTH_RUNNING" | grep -q "auth-service"; then
    ok "auth-service is running: $AUTH_RUNNING"
else
    fail "auth-service container is NOT running"
    info "All containers:"
    docker ps --format "  {{.Names}}\t{{.Status}}"
fi

if echo "$PROXY_RUNNING" | grep -q "flowise-proxy"; then
    ok "flowise-proxy is running: $PROXY_RUNNING"
else
    fail "flowise-proxy container is NOT running"
fi

# --------------------------------------------------------------------------
# 2. Check chatproxy-network exists
# --------------------------------------------------------------------------
echo ""
echo "--- 2. chatproxy-network ---"

if docker network inspect chatproxy-network &>/dev/null; then
    ok "chatproxy-network exists"
else
    fail "chatproxy-network does NOT exist"
    info "Available networks:"
    docker network ls --format "  {{.Name}}"
    echo ""
    warn "FIX: Create the shared network first, then restart both services:"
    echo "       docker network create chatproxy-network"
    echo "       cd auth-service       && docker compose -f docker-compose.dev.yml up -d"
    echo "       cd flowise-proxy-service-py && docker compose up -d"
fi

# --------------------------------------------------------------------------
# 3. Check both containers are on chatproxy-network
# --------------------------------------------------------------------------
echo ""
echo "--- 3. Containers connected to chatproxy-network ---"

NETWORK_MEMBERS=$(docker network inspect chatproxy-network --format "{{range .Containers}}{{.Name}} {{end}}" 2>/dev/null)
info "Members: $NETWORK_MEMBERS"

if echo "$NETWORK_MEMBERS" | grep -q "auth-service"; then
    ok "auth-service IS on chatproxy-network"
else
    fail "auth-service is NOT on chatproxy-network"
    warn "FIX: docker network connect chatproxy-network auth-service"
fi

if echo "$NETWORK_MEMBERS" | grep -q "flowise-proxy"; then
    ok "flowise-proxy IS on chatproxy-network"
else
    fail "flowise-proxy is NOT on chatproxy-network"
    warn "FIX: docker network connect chatproxy-network flowise-proxy"
fi

# --------------------------------------------------------------------------
# 4. Check EXTERNAL_AUTH_URL inside flowise-proxy
# --------------------------------------------------------------------------
echo ""
echo "--- 4. EXTERNAL_AUTH_URL inside flowise-proxy ---"

EXT_AUTH_URL=$(docker exec flowise-proxy printenv EXTERNAL_AUTH_URL 2>/dev/null)
if [ -z "$EXT_AUTH_URL" ]; then
    fail "EXTERNAL_AUTH_URL is not set inside flowise-proxy"
else
    ok "EXTERNAL_AUTH_URL = $EXT_AUTH_URL"
    if [[ "$EXT_AUTH_URL" == "http://auth-service:3000" ]]; then
        ok "URL format looks correct"
    else
        warn "Expected http://auth-service:3000 but got $EXT_AUTH_URL"
    fi
fi

# --------------------------------------------------------------------------
# 5. DNS resolution: can flowise-proxy resolve 'auth-service'?
# --------------------------------------------------------------------------
echo ""
echo "--- 5. DNS resolution inside flowise-proxy ---"

RESOLVED=$(docker exec flowise-proxy getent hosts auth-service 2>/dev/null)
if [ -n "$RESOLVED" ]; then
    ok "auth-service resolves to: $RESOLVED"
else
    fail "flowise-proxy cannot resolve hostname 'auth-service'"
    warn "This is the root cause — containers are not on the same Docker network"
fi

# --------------------------------------------------------------------------
# 6. TCP connectivity: can flowise-proxy reach auth-service:3000?
# --------------------------------------------------------------------------
echo ""
echo "--- 6. TCP connectivity flowise-proxy -> auth-service:3000 ---"

# Try curl first, fall back to nc
HTTP_CODE=$(docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://auth-service:3000/ 2>/dev/null)
if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    ok "TCP connection succeeded (HTTP $HTTP_CODE from /)"
else
    fail "TCP connection to auth-service:3000 failed (curl returned: '$HTTP_CODE')"
    # Try nc as fallback
    NC_RESULT=$(docker exec flowise-proxy sh -c "nc -zv auth-service 3000 2>&1" 2>/dev/null)
    info "nc result: $NC_RESULT"
fi

# --------------------------------------------------------------------------
# 7. Check the login endpoint specifically
# --------------------------------------------------------------------------
echo ""
echo "--- 7. POST /api/auth/login endpoint ---"

LOGIN_CODE=$(docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 \
    -X POST http://auth-service:3000/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"_diagnostic_probe_","password":"_probe_"}' 2>/dev/null)

if [ "$LOGIN_CODE" = "401" ] || [ "$LOGIN_CODE" = "400" ] || [ "$LOGIN_CODE" = "422" ]; then
    ok "Login endpoint reachable (returned HTTP $LOGIN_CODE — credentials wrong but server is UP)"
elif [ "$LOGIN_CODE" = "200" ]; then
    ok "Login endpoint reachable and returned 200 (unexpected with probe credentials)"
elif [ "$LOGIN_CODE" = "404" ]; then
    fail "Login endpoint returned 404 — wrong URL path? Check if auth-service uses /api/auth/login"
    info "Trying alternate paths..."
    for path in "/api/v1/auth/login" "/auth/login" "/login" "/api/login"; do
        CODE=$(docker exec flowise-proxy curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 -X POST "http://auth-service:3000${path}" \
            -H "Content-Type: application/json" \
            -d '{"username":"probe","password":"probe"}' 2>/dev/null)
        info "  $path -> HTTP $CODE"
    done
elif [ "$LOGIN_CODE" = "000" ] || [ -z "$LOGIN_CODE" ]; then
    fail "Login endpoint unreachable (connection refused or DNS failed)"
else
    warn "Login endpoint returned HTTP $LOGIN_CODE"
fi

# --------------------------------------------------------------------------
# 8. Check auth-service logs for startup errors
# --------------------------------------------------------------------------
echo ""
echo "--- 8. auth-service recent logs (last 20 lines) ---"
docker logs auth-service --tail=20 2>/dev/null || warn "Could not read auth-service logs"

# --------------------------------------------------------------------------
# 9. Summary
# --------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  SUMMARY / MOST COMMON FIXES"
echo "============================================================"
echo ""
echo "If DNS failed (step 5) or containers not on network (step 3):"
echo "  docker network create chatproxy-network   # if it doesn't exist"
echo "  docker network connect chatproxy-network auth-service"
echo "  docker network connect chatproxy-network flowise-proxy"
echo ""
echo "If auth-service is not running (step 1):"
echo "  cd auth-service && docker compose -f docker-compose.dev.yml up -d"
echo ""
echo "If EXTERNAL_AUTH_URL is wrong (step 4):"
echo "  Edit flowise-proxy-service-py/.env and set:"
echo "  EXTERNAL_AUTH_URL=http://auth-service:3000"
echo "  Then: cd flowise-proxy-service-py && docker compose up -d --force-recreate"
echo ""
echo "If the login path is wrong (step 7 returned 404):"
echo "  Check auth-service routes and update EXTERNAL_AUTH_URL path accordingly"
echo "============================================================"
