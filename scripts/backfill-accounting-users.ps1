<#!
.SYNOPSIS
    Ensure every auth-service user has a row in the accounting-service
    users-directory. Idempotent.

.DESCRIPTION
    Logs in as admin to auth-service, lists all users, fetches the
    accounting-service users-directory via the same admin token, computes
    the set of users present in auth but missing in accounting, and POSTs
    each missing record to accounting /api/users/ensure.

    Use this once after deploying the ensureAccountingUser hook to backfill
    pre-existing users that were created before the hook landed.

.PARAMETER AuthUrl
    Base URL of auth-service. Default: http://localhost:3000

.PARAMETER AccountingUrl
    Base URL of accounting-service. Default: http://localhost:3001

.PARAMETER AdminUsername
    Admin username for auth-service login. Default: admin

.PARAMETER AdminPassword
    Admin password for auth-service login. Default: admin@admin

.PARAMETER LogFile
    Optional master log file to append progress to.
#>
[CmdletBinding()]
param(
    [string]$AuthUrl = 'http://localhost:3000',
    [string]$AccountingUrl = 'http://localhost:3001',
    [string]$AdminUsername = 'admin',
    [string]$AdminPassword = 'admin@admin',
    [string]$LogFile
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Level, [string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    switch ($Level) {
        'OK'    { Write-Host "[OK]   $Message" -ForegroundColor Green }
        'WARN'  { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        'ERROR' { Write-Host "[FAIL] $Message" -ForegroundColor Red }
        default { Write-Host "[INFO] $Message" }
    }
    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue } catch {}
    }
}

Write-Log 'INFO' "Backfill started: AuthUrl=$AuthUrl AccountingUrl=$AccountingUrl"

# 1. Login to auth-service as admin
try {
    $loginBody = @{ username = $AdminUsername; password = $AdminPassword } | ConvertTo-Json
    $loginResp = Invoke-RestMethod -Uri "$AuthUrl/api/auth/login" -Method Post `
        -ContentType 'application/json' -Body $loginBody -TimeoutSec 30
} catch {
    Write-Log 'ERROR' "Admin login failed against $AuthUrl : $($_.Exception.Message)"
    exit 1
}

$token = $loginResp.accessToken
if (-not $token -and $loginResp.tokens) { $token = $loginResp.tokens.accessToken }
if (-not $token) {
    Write-Log 'ERROR' 'Admin login returned no accessToken'
    exit 1
}
$headers = @{ Authorization = "Bearer $token" }
Write-Log 'OK' 'Admin login OK'

# 2. List all auth-service users
try {
    $authUsers = Invoke-RestMethod -Uri "$AuthUrl/api/admin/users" -Headers $headers -TimeoutSec 60
} catch {
    Write-Log 'ERROR' "Could not list auth users: $($_.Exception.Message)"
    exit 1
}
# Some auth-service builds wrap the array in { users: [...] }
if ($authUsers -is [pscustomobject] -and $authUsers.PSObject.Properties.Name -contains 'users') {
    $authUsers = $authUsers.users
}
Write-Log 'INFO' "auth-service reports $($authUsers.Count) users"

# 3. Fetch accounting-service directory (via the admin token)
try {
    $dirResp = Invoke-RestMethod -Uri "$AccountingUrl/api/credits/users-directory" -Headers $headers -TimeoutSec 60
    $directory = $dirResp.users
} catch {
    Write-Log 'ERROR' "Could not fetch accounting users-directory: $($_.Exception.Message)"
    exit 1
}
if (-not $directory) { $directory = @() }
Write-Log 'INFO' "accounting-service users-directory has $($directory.Count) users"

# 4. Build a fast lookup of existing accounting userIds
$existing = @{}
foreach ($u in $directory) {
    if ($u.userId) { $existing[[string]$u.userId] = $true }
}

# 5. Diff and ensure each missing user
$ok = 0; $fail = 0; $skipped = 0
foreach ($u in $authUsers) {
    $sub = $u._id
    if (-not $sub) { $sub = $u.id }
    if (-not $sub) { $skipped++; continue }
    if ($existing.ContainsKey([string]$sub)) { $skipped++; continue }

    $payload = @{
        sub      = [string]$sub
        userId   = [string]$sub
        email    = $u.email
        username = $u.username
        role     = $u.role
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri "$AccountingUrl/api/users/ensure" -Method Post `
            -Headers $headers -ContentType 'application/json' -Body $payload -TimeoutSec 30 | Out-Null
        $ok++
        Write-Log 'OK' "ensured $($u.username) ($sub)"
    } catch {
        $fail++
        Write-Log 'WARN' "ensure failed for $($u.username): $($_.Exception.Message)"
    }
}

Write-Log 'INFO' "Backfill summary: ensured=$ok failed=$fail already_present_or_skipped=$skipped"
if ($fail -gt 0) {
    Write-Log 'ERROR' "$fail user(s) failed to ensure; review output."
    exit 1
}
Write-Log 'OK' 'Backfill completed cleanly'
exit 0
