#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Compare pre-patch and post-patch state files for forbidden password/data drift.

.PARAMETER PreFile
    Path to pre-patch state file

.PARAMETER PostFile
    Path to post-patch state file

.EXAMPLE
    .\check-patch-drift.ps1 -PreFile pre-state.env -PostFile post-state.env
#>
[CmdletBinding()]
param(
    [string]$PreFile,
    [string]$PostFile
)

function Parse-State {
    param([string]$Path)
    $map = @{}
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object {
            if ($_ -match '^(?<k>[^=]+)=(?<v>.*)$') {
                $map[$matches.k] = $matches.v
            }
        }
    }
    return $map
}

$pre = Parse-State $PreFile
$post = Parse-State $PostFile

# Secret fingerprints that must be identical pre/post (strict equality).
$secretKeys = @(
    "FLOWISE_API_KEY_SHA256",
    "FLOWISE_SECRETKEY_OVERWRITE_SHA256",
    "PROXY_MONGO_PASSWORD_SHA256",
    "PROXY_JWT_ACCESS_SECRET_SHA256",
    "PROXY_JWT_REFRESH_SECRET_SHA256",
    "AUTH_MONGO_INITDB_ROOT_PASSWORD_SHA256",
    "AUTH_JWT_ACCESS_SECRET_SHA256",
    "AUTH_JWT_REFRESH_SECRET_SHA256",
    "ACCOUNTING_DB_PASSWORD_SHA256",
    "ACCOUNTING_POSTGRES_PASSWORD_SHA256"
)

# Data-volume fingerprints. Counts are allowed to GROW (real activity during the
# patch window) and to recover from __MISSING__ (probe race when a DB container
# is mid-restart). Significant SHRINKAGE (>10%) or value->__MISSING__ still fails.
$dataKeys = @(
    "DATA_AUTH_USERS_COUNT",
    "DATA_PROXY_OBJECTS_COUNT",
    "DATA_FLOWISE_PG_EST_ROWS",
    "DATA_ACCOUNTING_PG_EST_ROWS"
)

$drifts = @()
$warnings = @()

function Get-StateValue {
    param($map, [string]$key)
    if ($map.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($map[$key])) {
        return $map[$key]
    }
    return "__MISSING__"
}

foreach ($key in $secretKeys) {
    $preVal = Get-StateValue $pre $key
    $postVal = Get-StateValue $post $key
    if ($preVal -ne $postVal) {
        $drifts += "${key}: PRE=$preVal POST=$postVal  (secret fingerprint changed - serious)"
    }
}

foreach ($key in $dataKeys) {
    $preVal = Get-StateValue $pre $key
    $postVal = Get-StateValue $post $key

    if ($preVal -eq $postVal) { continue }

    # Probe recovered: missing -> value is fine.
    if ($preVal -eq "__MISSING__") {
        $warnings += "${key}: PRE=__MISSING__ POST=$postVal  (probe recovered - ok)"
        continue
    }

    # Probe regressed: value -> missing means a DB is unreachable post-patch.
    if ($postVal -eq "__MISSING__") {
        $drifts += "${key}: PRE=$preVal POST=__MISSING__  (post-patch probe failed - DB unreachable?)"
        continue
    }

    # Both numeric: tolerate growth, flag shrinkage > 10%.
    $preNum = 0; $postNum = 0
    if ([int]::TryParse($preVal, [ref]$preNum) -and [int]::TryParse($postVal, [ref]$postNum)) {
        if ($postNum -ge $preNum) {
            $warnings += "${key}: PRE=$preVal POST=$postVal  (grew by $($postNum - $preNum) - real activity, ok)"
            continue
        }
        $loss = $preNum - $postNum
        $lossPct = if ($preNum -gt 0) { [math]::Round(100.0 * $loss / $preNum, 1) } else { 100.0 }
        if ($lossPct -le 10.0) {
            $warnings += "${key}: PRE=$preVal POST=$postVal  (lost $loss rows = ${lossPct}% - within tolerance)"
        } else {
            $drifts += "${key}: PRE=$preVal POST=$postVal  (lost $loss rows = ${lossPct}% - DATA LOSS)"
        }
        continue
    }

    # Non-numeric mismatch: treat as drift.
    $drifts += "${key}: PRE=$preVal POST=$postVal"
}

if ($warnings.Count -gt 0) {
    Write-Host "[INFO] Tolerated state changes:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

if ($drifts.Count -gt 0) {
    Write-Host "[FAIL] Password/data drift detected:" -ForegroundColor Red
    $drifts | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "[OK] No password/data drift detected" -ForegroundColor Green
    exit 0
}
