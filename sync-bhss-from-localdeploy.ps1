#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Safely analyze or prepare a merge from test/localdeploy into bhss.

.DESCRIPTION
    This script is intentionally non-destructive by default. It fetches refs,
    creates a backup branch from the target branch, prints commit and file
    diffs, classifies protected files, and can optionally prepare a
    --no-commit merge for manual review.

    Default mode is analysis only.

.PARAMETER SourceBranch
    Source branch to merge from. Defaults to test/localdeploy.

.PARAMETER TargetBranch
    Target branch to merge into. Defaults to bhss.

.PARAMETER Remote
    Git remote name. Defaults to origin.

.PARAMETER PrepareMerge
    Checks out the target branch, fast-forwards it from the remote, creates a
    backup branch, and runs a --no-ff --no-commit merge from SourceBranch.

.PARAMETER BackupBranchName
    Optional explicit backup branch name.

.PARAMETER ReportOnly
    Explicit analysis-only mode. This is the default.

.EXAMPLE
    .\sync-bhss-from-localdeploy.ps1

.EXAMPLE
    .\sync-bhss-from-localdeploy.ps1 -PrepareMerge
#>
[CmdletBinding()]
param(
    [string]$SourceBranch = 'test/localdeploy',
    [string]$TargetBranch = 'bhss',
    [string]$Remote = 'origin',
    [switch]$PrepareMerge,
    [switch]$ReportOnly,
    [string]$BackupBranchName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$logDir = Join-Path $scriptRoot 'logs'
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportPath = Join-Path $logDir "sync-bhss-from-localdeploy_$timestamp.log"

$protectedPatterns = @(
    '.env',
    '.env.*',
    'fleet-inventory.json',
    'wg-*.json',
    'wg-*.conf',
    '.local-version',
    'patch-windows-workstation.bat',
    'probe_and_fix_bhss.bat',
    'diagnose-bhss-state.ps1'
)

$protectedContentMarkers = @(
    'ai01.bhss.edu.hk',
    'bhss.edu.hk',
    'PATCH_TARGET=BHSS',
    'PATCH_TARGET is required. Set PATCH_TARGET=BHSS',
    'FLOWISE_PROXY_URL=http://ai01.bhss.edu.hk:8000',
    'PreferredHost "ai01.bhss.edu.hk"'
)

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $reportPath -Value $line

    switch ($Level) {
        'OK'   { Write-Host "[OK]   $Message" -ForegroundColor Green }
        'WARN' { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        'FAIL' { Write-Host "[FAIL] $Message" -ForegroundColor Red }
        default { Write-Host "[INFO] $Message" -ForegroundColor White }
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & git -C $scriptRoot @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        $joined = ($output | Out-String).Trim()
        throw "git $($Arguments -join ' ') failed: $joined"
    }

    return [PSCustomObject]@{
        Output = @($output)
        ExitCode = $exitCode
    }
}

function Test-PatternMatch {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Path -like $pattern -or $Path -like "*/$pattern" -or $Path -like "*$pattern") {
            return $true
        }
    }

    return $false
}

function Get-GitFileContent {
    param(
        [Parameter(Mandatory)]
        [string]$Revision,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = Invoke-Git -Arguments @('show', "$Revision`:$Path") -AllowFailure
    if ($result.ExitCode -ne 0) {
        return ''
    }

    return ($result.Output | Out-String)
}

function Test-ContentMarkerMatch {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$SourceRevision,
        [Parameter(Mandatory)]
        [string]$TargetRevision,
        [Parameter(Mandatory)]
        [string[]]$Markers
    )

    $sourceContent = Get-GitFileContent -Revision $SourceRevision -Path $Path
    $targetContent = Get-GitFileContent -Revision $TargetRevision -Path $Path
    $combinedContent = "$targetContent`n$sourceContent"

    foreach ($marker in $Markers) {
        if ($combinedContent -like "*$marker*") {
            return $true
        }
    }

    return $false
}

function Get-ChangedFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Range,
        [Parameter(Mandatory)]
        [string]$SourceRevision,
        [Parameter(Mandatory)]
        [string]$TargetRevision
    )

    $result = Invoke-Git -Arguments @('diff', '--name-status', $Range)
    $files = @()

    foreach ($line in $result.Output) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t+"
        if ($parts.Count -lt 2) { continue }

        $status = $parts[0].Trim()
        $path = $parts[$parts.Count - 1].Trim()
        $protectedByPattern = Test-PatternMatch -Path $path -Patterns $protectedPatterns
        $protectedByContent = Test-ContentMarkerMatch -Path $path -SourceRevision $SourceRevision -TargetRevision $TargetRevision -Markers $protectedContentMarkers
        $files += [PSCustomObject]@{
            Status = $status
            Path = $path
            Protected = ($protectedByPattern -or $protectedByContent)
            ProtectedByPattern = $protectedByPattern
            ProtectedByContent = $protectedByContent
        }
    }

    return $files
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host '================================================================' -ForegroundColor Cyan
    Add-Content -Path $reportPath -Value ''
    Add-Content -Path $reportPath -Value "==== $Title ===="
}

if (-not $PrepareMerge) {
    $ReportOnly = $true
}

Write-Section 'BHSS Sync Analysis'
Write-Log "Repo root: $scriptRoot"
Write-Log "Remote: $Remote"
Write-Log "Target branch: $TargetBranch"
Write-Log "Source branch: $SourceBranch"
Write-Log "Mode: $(if ($PrepareMerge) { 'prepare-merge' } else { 'report-only' })"

Invoke-Git -Arguments @('rev-parse', '--is-inside-work-tree') | Out-Null

$status = Invoke-Git -Arguments @('status', '--short')
if ($status.Output.Count -gt 0) {
    Write-Log 'Working tree is not clean. Stash or commit unrelated changes before preparing a merge.' 'WARN'
    foreach ($line in $status.Output) {
        Write-Host "  $line" -ForegroundColor DarkYellow
        Add-Content -Path $reportPath -Value "  $line"
    }

    if ($PrepareMerge) {
        throw 'Aborting prepare-merge because the working tree is not clean.'
    }
}
else {
    Write-Log 'Working tree is clean.' 'OK'
}

Write-Section 'Fetch'
Invoke-Git -Arguments @('fetch', $Remote, '--prune') | Out-Null
Write-Log "Fetched $Remote and pruned stale refs." 'OK'

$sourceRef = "$Remote/$SourceBranch"
$targetRef = "$Remote/$TargetBranch"

Invoke-Git -Arguments @('rev-parse', '--verify', $sourceRef) | Out-Null
Invoke-Git -Arguments @('rev-parse', '--verify', $targetRef) | Out-Null

Write-Section 'Branch Divergence'
$divergence = Invoke-Git -Arguments @('log', '--oneline', '--left-right', "$targetRef...$sourceRef")
if ($divergence.Output.Count -eq 0) {
    Write-Log 'No divergence between the fetched remote refs.' 'OK'
}
else {
    foreach ($line in $divergence.Output) {
        Write-Host "  $line" -ForegroundColor Gray
        Add-Content -Path $reportPath -Value "  $line"
    }
}

Write-Section 'File Diff Summary'
$intoTarget = Get-ChangedFiles -Range "$targetRef..$sourceRef" -SourceRevision $sourceRef -TargetRevision $targetRef
$intoSource = Get-ChangedFiles -Range "$sourceRef..$targetRef" -SourceRevision $targetRef -TargetRevision $sourceRef

Write-Log ("Files that would come from {0} into {1}: {2}" -f $SourceBranch, $TargetBranch, $intoTarget.Count)
Write-Log ("Files present on {0} but not on {1}: {2}" -f $TargetBranch, $SourceBranch, $intoSource.Count)

$protectedFiles = @($intoTarget | Where-Object { $_.Protected })
$sharedFiles = @($intoTarget | Where-Object { -not $_.Protected })

Write-Log ("Protected candidate files: {0}" -f $protectedFiles.Count) $(if ($protectedFiles.Count -gt 0) { 'WARN' } else { 'OK' })
foreach ($file in $protectedFiles) {
    $reasons = @()
    if ($file.ProtectedByPattern) { $reasons += 'pattern' }
    if ($file.ProtectedByContent) { $reasons += 'content' }
    $line = "  [PROTECTED:{0}] {1} {2}" -f ($reasons -join '+'), $file.Status, $file.Path
    Write-Host $line -ForegroundColor Yellow
    Add-Content -Path $reportPath -Value $line
}

Write-Log ("Shared candidate files: {0}" -f $sharedFiles.Count) 'OK'
foreach ($file in $sharedFiles) {
    $line = "  [SHARED] {0} {1}" -f $file.Status, $file.Path
    Write-Host $line -ForegroundColor Gray
    Add-Content -Path $reportPath -Value $line
}

if (-not $PrepareMerge) {
    Write-Section 'Next Step'
    Write-Log 'Analysis complete. Re-run with -PrepareMerge after reviewing the protected file list and ensuring the working tree is clean.' 'OK'
    Write-Log "Report written to $reportPath"
    exit 0
}

Write-Section 'Prepare Merge'
$currentBranch = (Invoke-Git -Arguments @('rev-parse', '--abbrev-ref', 'HEAD')).Output[0].Trim()
Write-Log "Current branch before merge prep: $currentBranch"

if (-not $BackupBranchName) {
    $BackupBranchName = "backup/{0}-before-{1}-{2}" -f ($TargetBranch -replace '/', '-'), ($SourceBranch -replace '/', '-'), (Get-Date -Format 'yyyyMMdd')
}

Invoke-Git -Arguments @('checkout', $TargetBranch) | Out-Null
Write-Log "Checked out $TargetBranch" 'OK'

Invoke-Git -Arguments @('pull', '--ff-only', $Remote, $TargetBranch) | Out-Null
Write-Log "Fast-forwarded $TargetBranch from $targetRef" 'OK'

$backupExists = Invoke-Git -Arguments @('rev-parse', '--verify', $BackupBranchName) -AllowFailure
if ($backupExists.ExitCode -eq 0) {
    Write-Log "Backup branch already exists: $BackupBranchName" 'WARN'
}
else {
    Invoke-Git -Arguments @('branch', $BackupBranchName, 'HEAD') | Out-Null
    Write-Log "Created backup branch: $BackupBranchName" 'OK'
}

$mergeAttempt = Invoke-Git -Arguments @('merge', '--no-ff', '--no-commit', $sourceRef) -AllowFailure
if ($mergeAttempt.ExitCode -ne 0) {
    Write-Log 'Merge needs manual conflict resolution. Protected files should usually keep the bhss side.' 'WARN'
}
else {
    Write-Log 'Prepared merge completed without immediate conflicts.' 'OK'
}

foreach ($file in $protectedFiles) {
    $checkoutResult = Invoke-Git -Arguments @('checkout', '--ours', '--', $file.Path) -AllowFailure
    if ($checkoutResult.ExitCode -eq 0) {
        Invoke-Git -Arguments @('add', '--', $file.Path) | Out-Null
        Write-Log "Kept target-branch version for protected file: $($file.Path)" 'OK'
    }
    else {
        Write-Log "Could not auto-keep protected file; review manually: $($file.Path)" 'WARN'
    }
}

Write-Section 'Prepared State'
$preparedStatus = Invoke-Git -Arguments @('status', '--short')
foreach ($line in $preparedStatus.Output) {
    Write-Host "  $line" -ForegroundColor Gray
    Add-Content -Path $reportPath -Value "  $line"
}

Write-Log 'Merge preparation is ready for manual review. Inspect git diff, test affected services, then commit manually if acceptable.' 'OK'
Write-Log "Report written to $reportPath"