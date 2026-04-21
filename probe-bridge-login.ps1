param(
    [string]$Username = "admin",
    [string]$Password = "admin@admin"
)

$ErrorActionPreference = "Continue"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Ok { param([string]$m) Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Fail { param([string]$m) Write-Host "[FAIL] $m" -ForegroundColor Red }

function Invoke-JsonPost {
    param(
        [string]$Url,
        [hashtable]$Body
    )

    $result = [ordered]@{
        Url = $Url
        Ok = $false
        StatusCode = 0
        Body = ""
        Error = ""
    }

    try {
        $json = $Body | ConvertTo-Json -Depth 5
        $resp = Invoke-WebRequest -Uri $Url -Method POST -ContentType "application/json" -Body $json -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $result.Ok = $true
        $result.StatusCode = [int]$resp.StatusCode
        $result.Body = $resp.Content
    }
    catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $result.StatusCode = [int]$ex.Response.StatusCode
        }
        $result.Error = $ex.Message

        try {
            if ($ex.Response -and $ex.Response.GetResponseStream()) {
                $reader = New-Object System.IO.StreamReader($ex.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
                if ($body) { $result.Body = $body }
            }
        }
        catch { }
    }

    return [pscustomobject]$result
}

function Test-Http200 {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return ($r.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

Write-Section "Bridge Login Probe"
Write-Host "Time      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Machine   : $env:COMPUTERNAME"
Write-Host "Username  : $Username"
Write-Host "Password  : <redacted>"

Write-Section "Container Presence"
$containers = @("bridge-ui", "flowise-proxy", "auth-service", "mongodb-proxy", "mongodb-auth", "postgres-accounting")
$present = @{}
foreach ($c in $containers) {
    $name = (docker ps --filter "name=^$c$" --format "{{.Names}}" 2>$null | Select-Object -First 1)
    if ($name -eq $c) {
        $present[$c] = $true
        Write-Ok "$c is running"
    } else {
        $present[$c] = $false
        Write-Warn "$c is NOT running"
    }
}

Write-Section "Health Endpoints"
$healthChecks = @(
    @{ Name = "bridge-ui"; Url = "http://localhost:3082" },
    @{ Name = "flowise-proxy"; Url = "http://localhost:8000/health" },
    @{ Name = "auth-service"; Url = "http://localhost:3000/health" }
)
foreach ($h in $healthChecks) {
    if (Test-Http200 -Url $h.Url) {
        Write-Ok "$($h.Name) health OK ($($h.Url))"
    } else {
        Write-Fail "$($h.Name) health FAILED ($($h.Url))"
    }
}

Write-Section "Auth Direct Login Test"
$authResult = Invoke-JsonPost -Url "http://localhost:3000/api/auth/login" -Body @{ username = $Username; password = $Password }
if ($authResult.Ok -and $authResult.StatusCode -eq 200) {
    Write-Ok "auth-service login succeeded (HTTP 200)"
} else {
    Write-Fail "auth-service login failed (HTTP $($authResult.StatusCode))"
    if ($authResult.Body) { Write-Host "  Body : $($authResult.Body)" }
    if ($authResult.Error) { Write-Host "  Error: $($authResult.Error)" }
}

Write-Section "Proxy Login Test (Bridge Path)"
$proxyResult = Invoke-JsonPost -Url "http://localhost:8000/api/v1/chat/authenticate" -Body @{ username = $Username; password = $Password }
if ($proxyResult.Ok -and $proxyResult.StatusCode -eq 200) {
    Write-Ok "flowise-proxy authenticate succeeded (HTTP 200)"
} else {
    Write-Fail "flowise-proxy authenticate failed (HTTP $($proxyResult.StatusCode))"
    if ($proxyResult.Body) { Write-Host "  Body : $($proxyResult.Body)" }
    if ($proxyResult.Error) { Write-Host "  Error: $($proxyResult.Error)" }
}

Write-Section "flowise-proxy Auth Link"
$extAuth = (docker exec flowise-proxy printenv EXTERNAL_AUTH_URL 2>$null | Select-Object -First 1)
if ($extAuth) {
    Write-Host "EXTERNAL_AUTH_URL (container): $extAuth"
    if ($extAuth -notmatch "auth-service:3000") {
        Write-Warn "EXTERNAL_AUTH_URL does not point to auth-service:3000"
    } else {
        Write-Ok "EXTERNAL_AUTH_URL points to auth-service:3000"
    }
} else {
    Write-Warn "Could not read EXTERNAL_AUTH_URL from flowise-proxy container"
}

Write-Section "Bridge Bundle API Target Scan"
Write-Host "Scanning built JS bundle for hardcoded API targets..."
$bundleScan = docker exec bridge-ui sh -c "grep -R -n -E 'aidcec-ai-agent.com|host.docker.internal:8000|localhost:8000|/api/v1/chat/authenticate' /usr/share/nginx/html/assets 2>/dev/null | head -n 80" 2>$null
if ($bundleScan) {
    $bundleScan | ForEach-Object { Write-Host "  $_" }
    if ($bundleScan -match "aidcec-ai-agent.com") {
        Write-Warn "Bridge bundle contains aidcec-ai-agent.com (likely wrong target for BHSS)"
    }
    if ($bundleScan -match "host.docker.internal:8000") {
        Write-Ok "Bridge bundle references host.docker.internal:8000"
    }
} else {
    Write-Warn "No API target string found in scanned bundle output"
}

Write-Section "Diagnosis"
if (($authResult.Ok -and $authResult.StatusCode -eq 200) -and ($proxyResult.Ok -and $proxyResult.StatusCode -eq 200)) {
    Write-Ok "Backend auth path is healthy (auth-service + flowise-proxy)."
    Write-Host "Likely UI-side issue:"
    Write-Host "  1) Bridge built with stale/wrong VITE_FLOWISE_PROXY_API_URL"
    Write-Host "  2) Browser cache serving old JS"
    Write-Host "  3) Wrong bridge instance URL"
    Write-Host ""
    Write-Host "Recommended next actions:"
    Write-Host "  - Rebuild bridge: patch-windows-workstation.bat bridge full"
    Write-Host "  - Hard refresh browser (Ctrl+F5)"
    Write-Host "  - Verify you are on the BHSS bridge URL"
    exit 0
}

if (($authResult.Ok -and $authResult.StatusCode -eq 200) -and -not ($proxyResult.Ok -and $proxyResult.StatusCode -eq 200)) {
    Write-Fail "auth-service works, but flowise-proxy auth path fails."
    Write-Host "Check flowise-proxy logs and EXTERNAL_AUTH_URL configuration."
    exit 1
}

if (-not ($authResult.Ok -and $authResult.StatusCode -eq 200)) {
    Write-Fail "auth-service login failed. Credentials/user state or auth backend issue."
    Write-Host "Check auth-service logs and verify admin account/password on BHSS."
    exit 1
}

Write-Warn "Probe completed with mixed results."
exit 1
