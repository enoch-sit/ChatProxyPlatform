# -------------------------------------------------------
# DB Secret Rotation -- Zero-Disclosure
# Rotates: /chatproxy/dev/db/accounting
#          /chatproxy/dev/db/flowise
# RDS does NOT exist yet -- updates Secrets Manager only.
# Passwords will be used when RDS is provisioned via Terraform.
# -------------------------------------------------------

$REGION   = "us-east-1"
$DB_USER  = "chatproxy_admin"

function New-DbPassword {
    # 32-char password: uppercase, lowercase, digits, safe special chars
    # Excludes: @ " / \ space (problematic in connection strings)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%^&*()-_=+[]{}|;:,.<>?'
    $rng   = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 64
    $rng.GetBytes($bytes)
    $pwd = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
    return $pwd.Substring(0, 32)
}

function Rotate-DbSecret {
    param([string]$SecretId)

    $tmp = Join-Path $env:TEMP "chatproxy-db-rotate.json"
    try {
        $newPass = New-DbPassword
        $payload = @{ DB_USER = $DB_USER; DB_PASSWORD = $newPass } | ConvertTo-Json -Compress
        $newPass = $null  # wipe from memory

        Set-Content -Path $tmp -Value $payload -Encoding Ascii
        $payload = $null

        $resp = aws secretsmanager put-secret-value `
            --region $REGION `
            --secret-id $SecretId `
            --secret-string file://$tmp | ConvertFrom-Json

        Write-Host "  Rotated $SecretId → VersionId: $($resp.VersionId)"
    }
    finally {
        Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=== Rotating /chatproxy/dev/db/accounting ==="
Rotate-DbSecret -SecretId "/chatproxy/dev/db/accounting"

Write-Host "`n=== Rotating /chatproxy/dev/db/flowise ==="
Rotate-DbSecret -SecretId "/chatproxy/dev/db/flowise"

Write-Host "`n=== Verifying versions ==="
foreach ($id in @("/chatproxy/dev/db/accounting", "/chatproxy/dev/db/flowise")) {
    Write-Host "`n$id"
    aws secretsmanager list-secret-version-ids `
        --region $REGION `
        --secret-id $id `
        --query "Versions[0:2].[VersionId,CreatedDate,VersionStages]" `
        --output table
}

Write-Host "`nDone. Both DB secrets rotated."
