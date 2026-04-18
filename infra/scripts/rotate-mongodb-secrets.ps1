# -------------------------------------------------------
# MongoDB Secret Rotation -- Zero-Disclosure
# Rotates: /chatproxy/dev/mongodb/auth   → { MONGODB_URI }
#          /chatproxy/dev/mongodb/proxy  → { MONGODB_URL }
# EC2 MongoDB does NOT exist yet -- updates Secrets Manager only.
# Reads current URI, replaces only the password portion, writes back.
# -------------------------------------------------------

$REGION = "us-east-1"

function New-MongoPassword {
    # 32-char password safe for MongoDB URI (no @, :, /, #, ?, space)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!$^&*()-_=+[]|;<>.'
    $rng   = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 64
    $rng.GetBytes($bytes)
    return (-join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })).Substring(0, 32)
}

function Rotate-MongoSecret {
    param(
        [string]$SecretId,
        [string]$UriField,    # MONGODB_URI or MONGODB_URL
        [string]$DbName       # database name
    )

    $tmp = Join-Path $env:TEMP "chatproxy-mongo-rotate.json"
    try {
        # Try to read existing URI to preserve host/port/dbname
        $scheme      = "mongodb://"
        $user        = "chatproxy_admin"
        $hostAndRest = "localhost:27017/$DbName"   # placeholder until EC2 exists

        $rawJson = cmd /c "aws secretsmanager get-secret-value --region $REGION --secret-id $SecretId --query SecretString --output text 2>nul"
        if ($LASTEXITCODE -eq 0 -and $rawJson) {
            $current    = $rawJson | ConvertFrom-Json
            $currentUri = $current.$UriField
            if ($currentUri -match '^(mongodb(?:\+srv)?://)([^:]+):([^@]+)@(.+)$') {
                $scheme      = $Matches[1]
                $user        = $Matches[2]
                $hostAndRest = $Matches[4]
                Write-Host "  Existing URI parsed -- preserving host/dbname."
            } else {
                Write-Host "  No parseable existing URI -- using placeholder host (update after EC2 provisioned)."
            }
            $current = $null; $currentUri = $null
        } else {
            Write-Host "  No existing value -- writing initial placeholder URI (update host after EC2 provisioned)."
        }

        $newPass = New-MongoPassword
        $newUri  = "${scheme}${user}:${newPass}@${hostAndRest}"
        $newPass = $null

        $payload = @{ $UriField = $newUri } | ConvertTo-Json -Compress
        $newUri  = $null

        Set-Content -Path $tmp -Value $payload -Encoding Ascii
        $payload = $null

        $resp = cmd /c "aws secretsmanager put-secret-value --region $REGION --secret-id $SecretId --secret-string file://$tmp" | ConvertFrom-Json

        Write-Host "  Rotated $SecretId → VersionId: $($resp.VersionId)"
    }
    finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=== Rotating /chatproxy/dev/mongodb/auth ==="
Rotate-MongoSecret -SecretId "/chatproxy/dev/mongodb/auth" -UriField "MONGODB_URI" -DbName "auth-db"

Write-Host "`n=== Rotating /chatproxy/dev/mongodb/proxy ==="
Rotate-MongoSecret -SecretId "/chatproxy/dev/mongodb/proxy" -UriField "MONGODB_URL" -DbName "proxy-db"

Write-Host "`n=== Verifying versions ==="
foreach ($id in @("/chatproxy/dev/mongodb/auth", "/chatproxy/dev/mongodb/proxy")) {
    Write-Host "`n$id"
    aws secretsmanager list-secret-version-ids `
        --region $REGION `
        --secret-id $id `
        --query "Versions[0:2].[VersionId,CreatedDate,VersionStages]" `
        --output table
}

Write-Host "`nDone. Both MongoDB secrets rotated."
