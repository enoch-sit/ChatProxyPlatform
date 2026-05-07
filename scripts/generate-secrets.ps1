#Requires -Version 5.1
<#
.SYNOPSIS
    Generate and populate ALL secrets for ChatProxy Platform services (PS port of generate_secrets.py).
.DESCRIPTION
    Uses RNGCryptoServiceProvider for cryptographically secure secrets.
    Copies .env.example to .env if .env is missing, then updates secrets in-place.
    FLOWISE_API_KEY is intentionally excluded -- must be created via Flowise UI after services start.
#>

param(
    [string]$WorkspaceRoot = $PSScriptRoot
)

# Resolve workspace root (scripts/ is one level below repo root)
if ($WorkspaceRoot -eq $PSScriptRoot) {
    $WorkspaceRoot = Split-Path $PSScriptRoot -Parent
}

# ── Crypto-safe random string ───────────────────────────────────────────────
function New-SecureRandomString {
    param(
        [int]$Length,
        [string]$Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.'
    )
    $rng    = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $bytes  = [byte[]]::new($Length * 4)
    $rng.GetBytes($bytes)
    $chars  = for ($i = 0; $i -lt $Length; $i++) {
        $idx = [BitConverter]::ToUInt32($bytes, $i * 4) % $Alphabet.Length
        $Alphabet[$idx]
    }
    $rng.Dispose()
    return -join $chars
}

# ── .env helper: copy example if missing ────────────────────────────────────
function Ensure-EnvFile {
    param([string]$ServiceDir)
    $envFile     = Join-Path $ServiceDir '.env'
    $envExample  = Join-Path $ServiceDir '.env.example'
    if (-not (Test-Path $envFile)) {
        if (Test-Path $envExample) {
            Copy-Item $envExample $envFile
            Write-Host "  [OK] Created $ServiceDir\.env from .env.example"
        } else {
            Write-Warning "  [WARN] No .env.example found in $ServiceDir -- skipping"
            return $false
        }
    }
    return $true
}

# ── .env helper: update/append a KEY=VALUE line ─────────────────────────────
function Set-EnvVar {
    param(
        [string]$EnvPath,
        [string]$Key,
        [string]$Value
    )
    $lines   = [System.IO.File]::ReadAllLines($EnvPath)
    $found   = $false
    $updated = for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        # Match KEY= or #KEY= or # KEY=
        if ($line -match "^#?\s*$([regex]::Escape($Key))=") {
            "${Key}=${Value}"
            $found = $true
        } else {
            $line
        }
    }
    if (-not $found) {
        $updated = @($updated) + @("", "# Generated secret", "${Key}=${Value}")
    }
    [System.IO.File]::WriteAllLines($EnvPath, $updated, [System.Text.UTF8Encoding]::new($false))
}

# ── Backup .env before modifying ────────────────────────────────────────────
function Backup-EnvFile {
    param([string]$EnvPath)
    if (Test-Path $EnvPath) {
        Copy-Item $EnvPath "${EnvPath}.backup" -Force
    }
}

function Get-EnvVarValue {
    param(
        [string]$EnvPath,
        [string]$Key
    )

    if (-not (Test-Path $EnvPath)) {
        return $null
    }

    foreach ($line in [System.IO.File]::ReadAllLines($EnvPath)) {
        if ($line -match "^\s*$([regex]::Escape($Key))=(.*)$") {
            return $matches[1].Trim()
        }
    }

    return $null
}

function Get-ReusableSecret {
    param(
        [string[]]$EnvPaths,
        [string[]]$Keys,
        [string[]]$DisallowedValues = @(),
        [string[]]$DisallowedPatterns = @()
    )

    foreach ($envPath in $EnvPaths) {
        foreach ($key in $Keys) {
            $value = Get-EnvVarValue -EnvPath $envPath -Key $key
            if ([string]::IsNullOrWhiteSpace($value)) {
                continue
            }

            if ($DisallowedValues -contains $value) {
                continue
            }

            $patternHit = $false
            foreach ($pattern in $DisallowedPatterns) {
                if ($value -match $pattern) {
                    $patternHit = $true
                    break
                }
            }

            if (-not $patternHit) {
                return $value
            }
        }
    }

    return $null
}

# ════════════════════════════════════════════════════════════════════════════
# 1. Generate secrets
# ════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "  Generating cryptographically secure secrets..." -ForegroundColor Cyan

$authEnvPath      = Join-Path $WorkspaceRoot 'auth-service\.env'
$accountingEnvPath = Join-Path $WorkspaceRoot 'accounting-service\.env'
$flowiseEnvPath   = Join-Path $WorkspaceRoot 'flowise\.env'
$proxyEnvPath     = Join-Path $WorkspaceRoot 'flowise-proxy-service-py\.env'

$jwtAccessSecret = Get-ReusableSecret -EnvPaths @($authEnvPath, $accountingEnvPath, $proxyEnvPath) -Keys @('JWT_ACCESS_SECRET') -DisallowedPatterns @('^your_generated_', '^dev_')
if (-not $jwtAccessSecret) { $jwtAccessSecret = New-SecureRandomString -Length 64 }

$jwtRefreshSecret = Get-ReusableSecret -EnvPaths @($authEnvPath, $accountingEnvPath, $proxyEnvPath) -Keys @('JWT_REFRESH_SECRET') -DisallowedPatterns @('^your_generated_', '^dev_')
if (-not $jwtRefreshSecret) { $jwtRefreshSecret = New-SecureRandomString -Length 64 }

$postgresPassword = Get-ReusableSecret -EnvPaths @($accountingEnvPath, $flowiseEnvPath) -Keys @('DB_PASSWORD', 'POSTGRES_PASSWORD', 'DATABASE_PASSWORD') -DisallowedValues @('postgres', 'postgres123')
if (-not $postgresPassword) { $postgresPassword = New-SecureRandomString -Length 32 }

$mongoPassword = Get-ReusableSecret -EnvPaths @($authEnvPath) -Keys @('MONGO_INITDB_ROOT_PASSWORD') -DisallowedPatterns @('^dev_')
if (-not $mongoPassword) { $mongoPassword = New-SecureRandomString -Length 32 }

$flowiseSecretKey = Get-ReusableSecret -EnvPaths @($flowiseEnvPath) -Keys @('FLOWISE_SECRETKEY_OVERWRITE') -DisallowedPatterns @('^changeme$', '^dev_')
if (-not $flowiseSecretKey) { $flowiseSecretKey = New-SecureRandomString -Length 32 }

$proxyJwtSecretKey = Get-ReusableSecret -EnvPaths @($proxyEnvPath) -Keys @('JWT_SECRET_KEY') -DisallowedPatterns @('^dev_')
if (-not $proxyJwtSecretKey) { $proxyJwtSecretKey = New-SecureRandomString -Length 64 }

Write-Host "  [OK] Secrets generated"

# ════════════════════════════════════════════════════════════════════════════
# 2. Ensure .env files exist (copy from .env.example if needed)
# ════════════════════════════════════════════════════════════════════════════
$services = @(
    'auth-service',
    'accounting-service',
    'flowise-proxy-service-py',
    'bridge',
    'flowise'
)

foreach ($svc in $services) {
    $dir = Join-Path $WorkspaceRoot $svc
    Ensure-EnvFile -ServiceDir $dir | Out-Null
}

# ════════════════════════════════════════════════════════════════════════════
# 3. Apply secrets to .env files
# ════════════════════════════════════════════════════════════════════════════

# JWT secrets -- same values across three services
$jwtServices = @('auth-service', 'accounting-service', 'flowise-proxy-service-py')
foreach ($svc in $jwtServices) {
    $envPath = Join-Path $WorkspaceRoot "$svc\.env"
    if (-not (Test-Path $envPath)) { continue }
    Backup-EnvFile $envPath
    Set-EnvVar -EnvPath $envPath -Key 'JWT_ACCESS_SECRET'  -Value $jwtAccessSecret
    Set-EnvVar -EnvPath $envPath -Key 'JWT_REFRESH_SECRET' -Value $jwtRefreshSecret
    Write-Host "  [OK] $svc -- JWT secrets updated"
}

# PostgreSQL -- flowise
$flowiseEnv = Join-Path $WorkspaceRoot 'flowise\.env'
if (Test-Path $flowiseEnv) {
    Backup-EnvFile $flowiseEnv
    Set-EnvVar -EnvPath $flowiseEnv -Key 'POSTGRES_PASSWORD'         -Value $postgresPassword
    Set-EnvVar -EnvPath $flowiseEnv -Key 'DATABASE_PASSWORD'         -Value $postgresPassword
    Set-EnvVar -EnvPath $flowiseEnv -Key 'FLOWISE_SECRETKEY_OVERWRITE' -Value $flowiseSecretKey
    Write-Host "  [OK] flowise -- PostgreSQL password + Flowise secret key updated"
}

# PostgreSQL -- accounting-service
$accountingEnv = Join-Path $WorkspaceRoot 'accounting-service\.env'
if (Test-Path $accountingEnv) {
    Backup-EnvFile $accountingEnv
    Set-EnvVar -EnvPath $accountingEnv -Key 'POSTGRES_PASSWORD' -Value $postgresPassword
    Set-EnvVar -EnvPath $accountingEnv -Key 'DB_PASSWORD'       -Value $postgresPassword
    Write-Host "  [OK] accounting-service -- PostgreSQL password updated"
}

# MongoDB -- auth-service
$authEnv = Join-Path $WorkspaceRoot 'auth-service\.env'
if (Test-Path $authEnv) {
    Backup-EnvFile $authEnv
    Set-EnvVar -EnvPath $authEnv -Key 'MONGO_INITDB_ROOT_PASSWORD' -Value $mongoPassword
    Write-Host "  [OK] auth-service -- MongoDB password updated"
}

# flowise-proxy-service-py -- JWT_SECRET_KEY + MONGODB_URL
$proxyEnv = Join-Path $WorkspaceRoot 'flowise-proxy-service-py\.env'
if (Test-Path $proxyEnv) {
    Backup-EnvFile $proxyEnv
    Set-EnvVar -EnvPath $proxyEnv -Key 'JWT_SECRET_KEY' -Value $proxyJwtSecretKey
    Set-EnvVar -EnvPath $proxyEnv -Key 'MONGO_PASSWORD' -Value $mongoPassword

    # MONGODB_URL: replace the whole line with the new password embedded
    $proxyLines = [System.IO.File]::ReadAllLines($proxyEnv)
    $urlFound   = $false
    $newMongoUrl = "MONGODB_URL=mongodb://admin:${mongoPassword}@mongodb-proxy:27017/flowise_proxy?authSource=admin"
    $proxyLines  = for ($i = 0; $i -lt $proxyLines.Count; $i++) {
        if ($proxyLines[$i] -match "^#?\s*MONGODB_URL=") {
            $newMongoUrl
            $urlFound = $true
        } else {
            $proxyLines[$i]
        }
    }
    if (-not $urlFound) {
        $proxyLines = @($proxyLines) + @("", "# Generated MongoDB connection string", $newMongoUrl)
    }
    [System.IO.File]::WriteAllLines($proxyEnv, $proxyLines, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  [OK] flowise-proxy-service-py -- JWT_SECRET_KEY + MONGODB_URL updated"
}

Write-Host ""
Write-Host "  [OK] All secrets generated and .env files updated" -ForegroundColor Green
Write-Host "  NOTE: FLOWISE_API_KEY must be set manually after Flowise UI starts." -ForegroundColor Yellow
Write-Host ""
