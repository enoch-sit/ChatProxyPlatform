#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Bump service version in version.json and optionally create a git tag.

.PARAMETER Service
    Service to bump, or 'all' to bump the top-level version.

.PARAMETER Type
    Semver bump type: major, minor, or patch.

.PARAMETER NoTag
    Skip creating a git tag.

.EXAMPLE
    .\infra\scripts\bump-version.ps1 -Service auth-service -Type patch
    .\infra\scripts\bump-version.ps1 -Service all -Type minor
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("auth-service", "accounting-service", "flowise-proxy", "bridge", "all")]
    [string]$Service,

    [Parameter(Mandatory)]
    [ValidateSet("major", "minor", "patch")]
    [string]$Type,

    [switch]$NoTag
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$versionFile = Join-Path $repoRoot "version.json"

if (-not (Test-Path $versionFile)) {
    throw "version.json not found at $versionFile"
}

$manifest = Get-Content $versionFile -Raw | ConvertFrom-Json

function Bump-SemVer {
    param([string]$Version, [string]$BumpType)
    $parts = $Version.Split('.')
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]

    switch ($BumpType) {
        "major" { $major++; $minor = 0; $patch = 0 }
        "minor" { $minor++; $patch = 0 }
        "patch" { $patch++ }
    }
    return "$major.$minor.$patch"
}

if ($Service -eq "all") {
    $oldVersion = $manifest.version
    $newVersion = Bump-SemVer $oldVersion $Type
    $manifest.version = $newVersion
    foreach ($svc in @("auth-service", "accounting-service", "flowise-proxy", "bridge")) {
        $manifest.services.$svc = $newVersion
    }
    $tagName = "v$newVersion"
    Write-Host "Bumped all services: $oldVersion -> $newVersion" -ForegroundColor Green
} else {
    $oldVersion = $manifest.services.$Service
    $newVersion = Bump-SemVer $oldVersion $Type
    $manifest.services.$Service = $newVersion
    # Also bump top-level if any service exceeds it
    if ([version]$newVersion -gt [version]$manifest.version) {
        $manifest.version = $newVersion
    }
    $tagName = "v$newVersion-$($Service -replace '-service','')"
    Write-Host "Bumped $Service : $oldVersion -> $newVersion" -ForegroundColor Green
}

$manifest.lastUpdated = (Get-Date -Format "yyyy-MM-dd")
$manifest | ConvertTo-Json -Depth 5 | Set-Content $versionFile -Encoding UTF8
Write-Host "Updated version.json" -ForegroundColor Green

if (-not $NoTag) {
    git add $versionFile
    git commit -m "chore: bump $Service to $newVersion"
    git tag $tagName
    Write-Host "Created git tag: $tagName" -ForegroundColor Cyan
    Write-Host "Run 'git push origin main --tags' to push." -ForegroundColor Yellow
}
