# -------------------------------------------------------
# SES SMTP Credential Rotation — Zero-Disclosure
# IAM user: chatproxy-ses-smtp
# Derives SMTP password from IAM secret key (never printed)
# -------------------------------------------------------

$IAM_USER   = "chatproxy-ses-smtp"
$REGION     = "us-east-1"
$SECRET_ID  = "/chatproxy/dev/ses"

# Step 1: List current keys (need the old key ID to delete later)
$keyList = aws iam list-access-keys --user-name $IAM_USER | ConvertFrom-Json
$oldKeys = $keyList.AccessKeyMetadata

if ($oldKeys.Count -ge 2) {
    Write-Error "IAM user already has 2 access keys. Delete one manually first:`n  aws iam delete-access-key --user-name $IAM_USER --access-key-id <ID>"
    exit 1
}

$oldKeyId = if ($oldKeys.Count -eq 1) { $oldKeys[0].AccessKeyId } else { $null }
Write-Host "Existing key to be replaced: $oldKeyId"

# Step 2: Create new IAM access key
$newKeyData = aws iam create-access-key --user-name $IAM_USER | ConvertFrom-Json
$newKeyId     = $newKeyData.AccessKey.AccessKeyId
$newSecretKey = $newKeyData.AccessKey.SecretAccessKey
Write-Host "New key ID created: $newKeyId"

# Step 3: Derive SES SMTP password (AWS v4 SMTP derivation — secret never displayed)
function Get-SesSmtpPassword {
    param([string]$SecretKey, [string]$Region)
    function HMAC256([byte[]]$key, [byte[]]$data) {
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = $key
        return $hmac.ComputeHash($data)
    }
    $kDate    = HMAC256 ([Text.Encoding]::UTF8.GetBytes("AWS4$SecretKey")) ([Text.Encoding]::UTF8.GetBytes("11111111"))
    $kRegion  = HMAC256 $kDate    ([Text.Encoding]::UTF8.GetBytes($Region))
    $kService = HMAC256 $kRegion  ([Text.Encoding]::UTF8.GetBytes("ses"))
    $kSigning = HMAC256 $kService ([Text.Encoding]::UTF8.GetBytes("aws4_request"))
    $rawSig   = HMAC256 $kSigning ([Text.Encoding]::UTF8.GetBytes("SendRawEmail"))
    $withVer  = New-Object byte[] ($rawSig.Length + 1)
    $withVer[0] = 0x04
    [Array]::Copy($rawSig, 0, $withVer, 1, $rawSig.Length)
    return [Convert]::ToBase64String($withVer)
}

$smtpPass = Get-SesSmtpPassword -SecretKey $newSecretKey -Region $REGION
$newSecretKey = $null  # wipe raw secret from memory immediately

# Step 4: Write to temp file and upload to Secrets Manager
$tmp = Join-Path $env:TEMP "chatproxy-ses-rotate.json"
try {
    $payload = @{ SMTP_USER = $newKeyId; SMTP_PASS = $smtpPass } | ConvertTo-Json -Compress
    Set-Content -Path $tmp -Value $payload -Encoding Ascii
    $smtpPass = $null; $payload = $null  # wipe from memory

    $resp = aws secretsmanager put-secret-value `
        --region $REGION `
        --secret-id $SECRET_ID `
        --secret-string file://$tmp | ConvertFrom-Json

    Write-Host "Secret updated. VersionId: $($resp.VersionId)"

    # Step 5: Delete old key (after secret is safely updated)
    if ($oldKeyId) {
        aws iam delete-access-key --user-name $IAM_USER --access-key-id $oldKeyId
        Write-Host "Old key deleted: $oldKeyId"
    }

    # Step 6: Verify
    Write-Host "`n--- IAM keys for $IAM_USER ---"
    aws iam list-access-keys --user-name $IAM_USER `
        --query "AccessKeyMetadata[*].[AccessKeyId,Status,CreateDate]" --output table

    Write-Host "`n--- Secrets Manager versions ---"
    aws secretsmanager list-secret-version-ids `
        --region $REGION --secret-id $SECRET_ID `
        --query "Versions[0:3].[VersionId,CreatedDate,VersionStages]" --output table
}
finally {
    Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
}