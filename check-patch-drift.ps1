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

# Keys that must NOT change during patch
$criticalKeys = @(
    "FLOWISE_API_KEY_SHA256",
    "FLOWISE_SECRETKEY_OVERWRITE_SHA256",
    "PROXY_MONGO_PASSWORD_SHA256",
    "PROXY_JWT_ACCESS_SECRET_SHA256",
    "PROXY_JWT_REFRESH_SECRET_SHA256",
    "AUTH_MONGO_INITDB_ROOT_PASSWORD_SHA256",
    "AUTH_JWT_ACCESS_SECRET_SHA256",
    "AUTH_JWT_REFRESH_SECRET_SHA256",
    "ACCOUNTING_DB_PASSWORD_SHA256",
    "ACCOUNTING_POSTGRES_PASSWORD_SHA256",
    "DATA_AUTH_USERS_COUNT",
    "DATA_PROXY_OBJECTS_COUNT",
    "DATA_FLOWISE_PG_EST_ROWS",
    "DATA_ACCOUNTING_PG_EST_ROWS"
)

$drifts = @()
foreach ($key in $criticalKeys) {
    $preVal = if ($pre.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($pre[$key])) { $pre[$key] } else { "__MISSING__" }
    $postVal = if ($post.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace($post[$key])) { $post[$key] } else { "__MISSING__" }
    
    if ($preVal -ne $postVal) {
        $drifts += "${key}: PRE=$preVal POST=$postVal"
    }
}

if ($drifts.Count -gt 0) {
    Write-Host "[FAIL] Password/data drift detected:" -ForegroundColor Red
    $drifts | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "[OK] No password/data drift detected" -ForegroundColor Green
    exit 0
}
