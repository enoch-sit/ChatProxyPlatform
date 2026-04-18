param(
  [string]$BaseBranch = "main",
  [string]$TargetBranch = "release/aws",
  [string]$OutputFile = "docs/LOGOUT_BRANCH_EVIDENCE.md"
)

$ErrorActionPreference = "Stop"

$criticalFiles = @(
  "bridge/src/api/auth.ts",
  "bridge/src/store/authStore.ts",
  "bridge/src/components/auth/ProtectedRoute.tsx",
  "flowise-proxy-service-py/app/api/chat.py",
  "flowise-proxy-service-py/app/auth/middleware.py",
  "auth-service/src/routes/index.ts",
  "auth-service/src/auth/auth.service.ts",
  "auth-service/src/auth/token.service.ts",
  "auth-service/src/models/token.model.ts",
  "auth-service/docker-compose.dev.yml"
)

$frontendPattern = "authenticate|refresh|revoke|logout|VITE_FLOWISE_PROXY_API_URL|API_BASE_URL|detail|message"
$backendPattern = "revoke|refresh|authenticate|validate_user_permissions|role|logout"

function Get-BranchSha {
  param([string]$Branch)
  return (git rev-parse $Branch).Trim()
}

function Get-FilteredLines {
  param(
    [string]$Branch,
    [string]$Path,
    [string]$Pattern
  )

  $content = git show "$Branch`:$Path"
  if ($LASTEXITCODE -ne 0) {
    return @("(unable to read ${Branch}:$Path)")
  }

  $matches = $content | Select-String -Pattern $Pattern
  if (-not $matches) {
    return @("(no matches)")
  }

  return $matches | ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() }
}

$baseSha = Get-BranchSha -Branch $BaseBranch
$targetSha = Get-BranchSha -Branch $TargetBranch
$currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()

$changedCritical = git diff --name-only "$BaseBranch...$TargetBranch" -- $criticalFiles
if (-not $changedCritical) {
  $changedCritical = @()
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("# Logout Branch Evidence")
$report.Add("")
$report.Add("Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("Base branch: $BaseBranch ($baseSha)")
$report.Add("Target branch: $TargetBranch ($targetSha)")
$report.Add("Current branch: $currentBranch")
$report.Add("")
$report.Add("## Changed Critical Files")
if ($changedCritical.Count -eq 0) {
  $report.Add("- none")
} else {
  foreach ($file in $changedCritical) {
    $report.Add("- $file")
  }
}
$report.Add("")

$report.Add("## Frontend Auth Evidence")
$report.Add("")
$report.Add("### ${BaseBranch}: bridge/src/api/auth.ts")
$report.Add('```')
(Get-FilteredLines -Branch $BaseBranch -Path "bridge/src/api/auth.ts" -Pattern $frontendPattern) | ForEach-Object { $report.Add($_) }
$report.Add('```')
$report.Add("")
$report.Add("### ${TargetBranch}: bridge/src/api/auth.ts")
$report.Add('```')
(Get-FilteredLines -Branch $TargetBranch -Path "bridge/src/api/auth.ts" -Pattern $frontendPattern) | ForEach-Object { $report.Add($_) }
$report.Add('```')
$report.Add("")

$report.Add("## Backend Auth Evidence")
$report.Add("")
$report.Add("### ${BaseBranch}: flowise-proxy-service-py/app/api/chat.py")
$report.Add('```')
(Get-FilteredLines -Branch $BaseBranch -Path "flowise-proxy-service-py/app/api/chat.py" -Pattern $backendPattern) | ForEach-Object { $report.Add($_) }
$report.Add('```')
$report.Add("")
$report.Add("### ${TargetBranch}: flowise-proxy-service-py/app/api/chat.py")
$report.Add('```')
(Get-FilteredLines -Branch $TargetBranch -Path "flowise-proxy-service-py/app/api/chat.py" -Pattern $backendPattern) | ForEach-Object { $report.Add($_) }
$report.Add('```')
$report.Add("")

$report.Add("## Diff Excerpts")
$report.Add("")
$diffTargets = @(
  "bridge/src/api/auth.ts",
  "bridge/src/store/authStore.ts",
  "flowise-proxy-service-py/app/api/chat.py",
  "flowise-proxy-service-py/app/auth/middleware.py",
  "auth-service/src/routes/index.ts",
  "auth-service/src/auth/auth.service.ts"
)

foreach ($path in $diffTargets) {
  $report.Add("### $path")
  $report.Add('```')
  $diff = git diff "$BaseBranch...$TargetBranch" -- $path
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($diff)) {
    $report.Add("(no diff)")
  } else {
    $lines = $diff -split "`r?`n"
    foreach ($line in ($lines | Select-Object -First 120)) {
      $report.Add($line)
    }
    if ($lines.Count -gt 120) {
      $report.Add("... (truncated)")
    }
  }
  $report.Add('```')
  $report.Add("")
}

$dir = Split-Path -Parent $OutputFile
if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path $dir)) {
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$report | Set-Content -Path $OutputFile -Encoding UTF8
Write-Output "Wrote evidence report to $OutputFile"
