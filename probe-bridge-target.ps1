param(
    [string]$PreferredHost = "",
    [int]$ProxyPort = 8000,
    [int]$BridgePort = 3082
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

function Test-Url {
    param([string]$Url)

    $result = [ordered]@{
        Url = $Url
        Reachable = $false
        Status = 0
        Error = ""
    }

    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
        $result.Reachable = $true
        $result.Status = [int]$r.StatusCode
    }
    catch {
        $ex = $_.Exception
        if ($ex.Response -and $ex.Response.StatusCode) {
            $result.Status = [int]$ex.Response.StatusCode
        }
        $result.Error = $ex.Message
    }

    return [pscustomobject]$result
}

Write-Section "Bridge Target Probe"
Write-Host "Time      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Machine   : $env:COMPUTERNAME"
Write-Host "Preferred : $PreferredHost"
Write-Host "ProxyPort : $ProxyPort"
Write-Host "BridgePort: $BridgePort"

$hosts = New-Object System.Collections.Generic.List[string]
if ($PreferredHost) { [void]$hosts.Add($PreferredHost) }

# Add machine name and FQDN candidates.
[void]$hosts.Add($env:COMPUTERNAME)
try {
    $fqdn = ([System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)).HostName
    if ($fqdn) { [void]$hosts.Add($fqdn) }
} catch { }

# Add local non-loopback IPv4 addresses.
try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^127\.' -and $_.IPAddress -notmatch '^169\.254\.' } |
        Select-Object -ExpandProperty IPAddress -Unique
    foreach ($ip in $ips) { [void]$hosts.Add($ip) }
} catch { }

# Add host from existing bundle scan when possible (if bridge-ui is running).
$bundleLines = docker exec bridge-ui sh -c "grep -R -n -E 'https?://[^\"\047 ]+' /usr/share/nginx/html/assets 2>/dev/null | head -n 80" 2>$null
if ($bundleLines) {
    foreach ($line in $bundleLines) {
        if ($line -match 'https?://\S+') {
            $trimChars = [char[]](44,59,41,93,34,39)
            $url = $matches[0].TrimEnd($trimChars)
            try {
                $u = [uri]$url
                if ($u.Host) { [void]$hosts.Add($u.Host) }
            } catch { }
        }
    }
}

# Deduplicate and filter junk tokens.
$hostSet = $hosts |
    Where-Object { $_ -and $_.Trim() -ne "" } |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -notmatch '^localhost$' -or $true } |
    Select-Object -Unique

Write-Section "Candidate Hosts"
$hostSet | ForEach-Object { Write-Host "  $_" }

Write-Section "Proxy Endpoint Tests"
$tests = New-Object System.Collections.Generic.List[object]

# Always include localhost candidates explicitly.
$probeUrls = New-Object System.Collections.Generic.List[string]
[void]$probeUrls.Add("http://localhost:$ProxyPort/health")
[void]$probeUrls.Add("https://localhost:$ProxyPort/health")

foreach ($h in $hostSet) {
    [void]$probeUrls.Add("http://${h}:$ProxyPort/health")
    [void]$probeUrls.Add("https://${h}:$ProxyPort/health")
}

$probeUrls = $probeUrls | Select-Object -Unique

foreach ($u in $probeUrls) {
    $r = Test-Url -Url $u
    [void]$tests.Add($r)
    if ($r.Reachable -and $r.Status -eq 200) {
        Write-Ok "$($r.Url) -> HTTP $($r.Status)"
    } else {
        if ($r.Status -gt 0) {
            Write-Warn "$($r.Url) -> HTTP $($r.Status)"
        } else {
            Write-Warn "$($r.Url) -> unreachable"
        }
    }
}

Write-Section "Recommendation"
$good = $tests | Where-Object { $_.Reachable -and $_.Status -eq 200 }

if (-not $good -or $good.Count -eq 0) {
    Write-Fail "No reachable proxy /health endpoint found on tested hosts."
    Write-Host "Check flowise-proxy publish/port/firewall first."
    exit 1
}

# Prefer PreferredHost if provided and reachable; else choose first non-localhost reachable HTTP/HTTPS.
$recommended = $null
if ($PreferredHost) {
    $preferredLiteral = "//${PreferredHost}:$ProxyPort/health"
    $recommended = $good | Where-Object { $_.Url -like "*$preferredLiteral" } | Select-Object -First 1
}
if (-not $recommended) {
    $recommended = $good | Where-Object { $_.Url -notmatch "//localhost:" } | Select-Object -First 1
}
if (-not $recommended) {
    $recommended = $good | Select-Object -First 1
}

$flowiseProxyUrl = $recommended.Url -replace "/health`$", ""

Write-Ok "Use this for bridge build target:"
Write-Host ""
Write-Host "  set FLOWISE_PROXY_URL=$flowiseProxyUrl" -ForegroundColor Cyan
Write-Host "  patch-windows-workstation.bat bridge full" -ForegroundColor Cyan
Write-Host "  set FLOWISE_PROXY_URL=" -ForegroundColor Cyan

Write-Host ""
Write-Host "If browser still serves old JS, do Ctrl+F5 and re-test login." 

exit 0
