#Requires -Version 5.1
# Fix Docker credential store for non-interactive (SSH/fleet) sessions.
# When Docker uses desktop-windows credsStore in an SSH logon session,
# it fails with "A specified logon session does not exist."
# This script writes a config.json that disables the credential helper.

$dockerDir    = "$env:USERPROFILE\.docker"
$configPath   = "$dockerDir\config.json"

New-Item -ItemType Directory -Force -Path $dockerDir | Out-Null

# Check if there's an existing config to preserve auths
$existing = $null
if (Test-Path $configPath) {
    try { $existing = Get-Content $configPath -Raw | ConvertFrom-Json } catch {}
}

# Build config: completely omit credsStore so Docker uses auths{} only
# An empty-string value still triggers the helper; the key must not exist.
if ($existing -and $existing.auths) {
    $json = [ordered]@{ auths = $existing.auths } | ConvertTo-Json -Depth 5
} else {
    $json = '{}'
}
[System.IO.File]::WriteAllText($configPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "[OK] Docker credential store disabled for user $env:USERNAME"
Write-Host "     Config written to: $configPath"
