#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Discover the working flowise-proxy endpoint on this machine.

.DESCRIPTION
    Probes localhost and candidate hosts to find which protocol/port/host 
    combination works for the flowise-proxy health endpoint.
    
    Helps identify the correct FLOWISE_PROXY_URL for bridge builds.

.PARAMETER PreferredHost
    Preferred hostname/IP to test (e.g., "ai01.bhss.edu.hk").
    If provided and reachable, will be recommended.

.PARAMETER ProxyPort
    Port to test (default 8000). Probes both HTTP and HTTPS on this port.

.EXAMPLE
    .\probe-bridge-target.ps1 -PreferredHost "ai01.bhss.edu.hk"
    .\probe-bridge-target.ps1 -PreferredHost "ai01.bhss.edu.hk" -ProxyPort 8000
#>
[CmdletBinding()]
param(
    [string]$PreferredHost = "",
    [int]$ProxyPort = 8000
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Flowise Proxy Endpoint Discovery" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Time       : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Machine    : $env:COMPUTERNAME"
Write-Host "PreferredHost: $PreferredHost"
Write-Host "ProxyPort  : $ProxyPort"
Write-Host ""

# Build list of candidates to test
$candidates = @()

if ($PreferredHost) {
    $candidates += @($PreferredHost)
}

# Add localhost
$candidates += @("localhost", "127.0.0.1")

# Add machine name
$candidates += @($env:COMPUTERNAME)

# Try to get FQDN
try {
    $fqdn = ([System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)).HostName
    if ($fqdn -and $fqdn -ne $env:COMPUTERNAME) {
        $candidates += @($fqdn)
    }
} catch { }

# Add local non-loopback IPs
try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\.254\." } |
        Select-Object -ExpandProperty IPAddress -Unique
    $candidates += $ips
} catch { }

# Deduplicate
$candidates = $candidates | Where-Object { $_ } | Select-Object -Unique

Write-Host "Testing candidates:"
$candidates | ForEach-Object { Write-Host "  - $_" }
Write-Host ""

# Test each candidate with both HTTP and HTTPS
$results = @()

foreach ($candidate in $candidates) {
    foreach ($scheme in @("http", "https")) {
        $url = "${scheme}://${candidate}:${ProxyPort}/health"
        
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Host "[OK]    $url -> HTTP $($response.StatusCode)" -ForegroundColor Green
                $results += @{
                    Url = $url
                    Scheme = $scheme
                    Host = $candidate
                    Port = $ProxyPort
                    Status = $response.StatusCode
                    Working = $true
                }
            }
        } catch {
            $statusCode = 0
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            
            if ($statusCode -gt 0) {
                Write-Host "[WARN]  $url -> HTTP $statusCode" -ForegroundColor Yellow
            } else {
                Write-Host "[FAIL]  $url -> unreachable" -ForegroundColor Gray
            }
        }
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Results" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if ($results.Count -eq 0) {
    Write-Host "[FAIL] No working endpoint found!" -ForegroundColor Red
    Write-Host "Check that flowise-proxy is running and accessible." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found $($results.Count) working endpoint(s):" -ForegroundColor Green
$results | ForEach-Object {
    Write-Host "  $($_.Url)" -ForegroundColor Green
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Recommendation" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Pick the best result
$recommended = $null

# Prefer PreferredHost if provided and reachable
if ($PreferredHost) {
    $recommended = $results | Where-Object { $_.Host -eq $PreferredHost } | Select-Object -First 1
}

# Otherwise prefer HTTPS if available
if (-not $recommended) {
    $recommended = $results | Where-Object { $_.Scheme -eq "https" } | Select-Object -First 1
}

# Otherwise prefer non-localhost
if (-not $recommended) {
    $recommended = $results | Where-Object { $_.Host -notmatch "^localhost$" } | Where-Object { $_.Host -notmatch "^127\.0\.0\.1$" } | Select-Object -First 1
}

# Last resort: just take first working one
if (-not $recommended) {
    $recommended = $results[0]
}

$proxyUrl = $recommended.Url -replace "/health$", ""

Write-Host "Recommended URL:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  $proxyUrl" -ForegroundColor Green
Write-Host ""
Write-Host "To use this for bridge patching:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  set FLOWISE_PROXY_URL=$proxyUrl" -ForegroundColor Cyan
Write-Host "  patch-windows-workstation.bat bridge full" -ForegroundColor Cyan
Write-Host ""
Write-Host "  (or for quick patch with no rebuild:)" -ForegroundColor Gray
Write-Host "  set FLOWISE_PROXY_URL=$proxyUrl" -ForegroundColor Gray
Write-Host "  patch-windows-workstation.bat bridge quick" -ForegroundColor Gray
Write-Host ""

exit 0
