# fix_flowise_db_secret.ps1
# Generates a fresh password and stores it in Secrets Manager.
# Uses ConvertTo-Json for reliable escaping on Windows PowerShell.
# The password is never written to disk.

$newPass = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })

$json = [PSCustomObject]@{
  POSTGRES_USER     = "chatproxy_admin"
  POSTGRES_PASSWORD = $newPass
} | ConvertTo-Json -Compress

# Write to temp file to avoid Windows quote-stripping on CLI args
$tmpFile = [System.IO.Path]::GetTempFileName()
$json | Out-File -FilePath $tmpFile -Encoding utf8 -NoNewline

try {
  aws secretsmanager put-secret-value --region us-east-1 --secret-id /chatproxy/dev/db/flowise --secret-string "file://$tmpFile"
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] /chatproxy/dev/db/flowise updated ($($newPass.Length) char password)" -ForegroundColor Green
  } else {
    Write-Host "[FAILED] Check AWS CLI output above" -ForegroundColor Red
  }
} finally {
  Remove-Item $tmpFile -Force
}
