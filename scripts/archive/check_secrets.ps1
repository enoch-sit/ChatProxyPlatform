$secrets = @{
  "/chatproxy/dev/jwt"             = @("JWT_ACCESS_SECRET", "JWT_REFRESH_SECRET")
  "/chatproxy/dev/db/accounting"   = @("DB_USER", "DB_PASSWORD")
  "/chatproxy/dev/db/flowise"      = @("POSTGRES_USER", "POSTGRES_PASSWORD")
  "/chatproxy/dev/mongodb/auth"    = @("MONGODB_URI")
  "/chatproxy/dev/mongodb/proxy"   = @("MONGODB_URL")
  "/chatproxy/dev/flowise/api-key" = @("FLOWISE_API_KEY")
  "/chatproxy/dev/ses"             = @("SMTP_USER", "SMTP_PASS")
}

foreach ($secretId in ($secrets.Keys | Sort-Object)) {
  try {
    $raw = aws secretsmanager get-secret-value --secret-id $secretId --region us-east-1 --query SecretString --output text 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[NOT FOUND] $secretId" -ForegroundColor Red
      continue
    }
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    Write-Host "`n$secretId"
    foreach ($key in $secrets[$secretId]) {
      $val = $obj.$key
      if ($val -and $val.Length -gt 0) {
        Write-Host "  [OK]    $key  ($($val.Length) chars)" -ForegroundColor Green
      } else {
        Write-Host "  [EMPTY] $key" -ForegroundColor Red
      }
    }
  } catch {
    Write-Host "[ERROR] $secretId => $_" -ForegroundColor Yellow
  }
}
Write-Host ""
