# fix_flowise_apikey_secret.ps1
# Wraps the Flowise API key in JSON and stores it in Secrets Manager.
# Key is read as SecureString — never visible on screen.
# Uses ConvertTo-Json for reliable escaping on Windows PowerShell.

$secure = Read-Host -AsSecureString "Paste your Flowise API key (input hidden)"
$bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

if ([string]::IsNullOrWhiteSpace($plain)) {
  Write-Host "[FAILED] No key provided" -ForegroundColor Red
  exit 1
}

$json = [PSCustomObject]@{ FLOWISE_API_KEY = $plain } | ConvertTo-Json -Compress

$plain = $null   # clear sensitive variable

# Write to temp file to avoid Windows quote-stripping on CLI args
$tmpFile = [System.IO.Path]::GetTempFileName()
$json | Out-File -FilePath $tmpFile -Encoding utf8 -NoNewline

try {
  aws secretsmanager put-secret-value --region us-east-1 --secret-id /chatproxy/dev/flowise/api-key --secret-string "file://$tmpFile"
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] /chatproxy/dev/flowise/api-key updated as JSON" -ForegroundColor Green
  } else {
    Write-Host "[FAILED] Check AWS CLI output above" -ForegroundColor Red
  }
} finally {
  Remove-Item $tmpFile -Force
}
