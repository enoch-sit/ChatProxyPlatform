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

# Build config: explicitly set empty auths for docker.io so Docker skips
# the credential helper for public registries (Docker Desktop v4+ calls
# docker-credential-desktop even when credsStore is absent; an explicit
# empty auth entry prevents that lookup for the registry).
$auths = [ordered]@{}
if ($existing -and $existing.auths) {
    # Preserve any existing auth entries
    $existing.auths.PSObject.Properties | ForEach-Object { $auths[$_.Name] = $_.Value }
}
# Ensure docker.io has an empty entry so no credential helper is called
if (-not $auths.Contains('https://index.docker.io/v1/')) {
    $auths['https://index.docker.io/v1/'] = [ordered]@{}
}
$json = [ordered]@{ auths = $auths } | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($configPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "[OK] Docker credential store disabled for user $env:USERNAME"
Write-Host "     Config written to: $configPath"
