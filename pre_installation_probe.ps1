#!/usr/bin/env pwsh
<#!
.SYNOPSIS
    Read-only pre-installation probe for ChatProxy Windows workstations.

.DESCRIPTION
    Inspects repo state, target branch readiness, workstation prerequisites,
    Docker availability, and local install signals to decide whether this
    machine should:
      - run setup.ps1
      - fix blockers first
      - avoid a fresh install and use diagnose.ps1 / patch.ps1 instead

.PARAMETER ExpectedBranch
    Branch the workstation should be on before installation. If omitted, the
    probe uses the current checked-out deployment branch when it is
    test/localdeploy or test/deploylocal; otherwise it falls back to
    test/localdeploy.

.PARAMETER AsJson
    Emit the full probe result as JSON.

.EXAMPLE
    .\pre_installation_probe.ps1

.EXAMPLE
    .\pre_installation_probe.ps1 -ExpectedBranch test/localdeploy -AsJson

.EXAMPLE
    .\pre_installation_probe.ps1 -ExpectedBranch test/deploylocal
#>
[CmdletBinding()]
param(
    [string]$ExpectedBranch = "",
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

$defaultExpectedBranch = 'test/localdeploy'
$autoDetectedDeploymentBranches = @('test/localdeploy', 'test/deploylocal')

$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)]
        [string]$Area,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet("ok", "warn", "fail")]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Recommendation = ""
    )

    $checks.Add([pscustomobject]@{
        Area           = $Area
        Name           = $Name
        Status         = $Status
        Message        = $Message
        Recommendation = $Recommendation
    }) | Out-Null
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$Arguments = @()
    )

    if (-not (Test-Command $Command)) {
        return [pscustomobject]@{
            Success  = $false
            Output   = ""
            ExitCode = 127
        }
    }

    try {
        $output = & $Command @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            Success  = ($exitCode -eq 0)
            Output   = ($output | Out-String).Trim()
            ExitCode = $exitCode
        }
    }
    catch {
        return [pscustomobject]@{
            Success  = $false
            Output   = $_.Exception.Message
            ExitCode = 1
        }
    }
}

function Get-FirstVersionString {
    param([string]$Text)

    if (-not $Text) {
        return $null
    }

    $match = [regex]::Match($Text, '\d+(?:\.\d+){0,3}')
    if ($match.Success) {
        return $match.Value
    }

    return $null
}

function Convert-ToComparableVersion {
    param([string]$Value)

    if (-not $Value) {
        return $null
    }

    $parts = @($Value -split '\.')
    while ($parts.Count -lt 3) {
        $parts += '0'
    }
    if ($parts.Count -gt 4) {
        $parts = $parts[0..3]
    }

    try {
        return [Version]($parts -join '.')
    }
    catch {
        return $null
    }
}

function Get-ConstraintVersion {
    param([string]$Constraint)

    if (-not $Constraint) {
        return $null
    }

    return Get-FirstVersionString -Text $Constraint
}

function Get-StatusRank {
    param([string]$Status)

    switch ($Status) {
        'fail' { return 2 }
        'warn' { return 1 }
        default { return 0 }
    }
}

function Get-WorstStatus {
    param([string[]]$Statuses)

    if ($Statuses -contains 'fail') {
        return 'fail'
    }
    if ($Statuses -contains 'warn') {
        return 'warn'
    }
    return 'ok'
}

function Get-PortUsage {
    param([int[]]$Ports)

    $results = @()
    foreach ($port in $Ports) {
        try {
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
        }
        catch {
            $listeners = @()
        }

        foreach ($listener in $listeners) {
            $processName = $null
            try {
                $processName = (Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue).ProcessName
            }
            catch { }

            $results += [pscustomobject]@{
                Port        = $port
                ProcessId   = $listener.OwningProcess
                ProcessName = $processName
            }
        }
    }

    return $results
}

function Write-Header {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " ChatProxy Pre-Installation Probe" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host " Time           : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host " Machine        : $env:COMPUTERNAME"
    Write-Host " Directory      : $scriptRoot"
    Write-Host " ExpectedBranch : $ExpectedBranch"
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Write-CheckOutput {
    param($Check)

    $prefix = switch ($Check.Status) {
        'ok'   { '[OK]  ' }
        'warn' { '[WARN]' }
        'fail' { '[FAIL]' }
    }

    $color = switch ($Check.Status) {
        'ok'   { 'Green' }
        'warn' { 'Yellow' }
        'fail' { 'Red' }
    }

    Write-Host "$prefix [$($Check.Area)] $($Check.Name): $($Check.Message)" -ForegroundColor $color
    if ($Check.Recommendation) {
        Write-Host "       $($Check.Recommendation)" -ForegroundColor DarkGray
    }
}

$requiredFiles = @(
    'setup.ps1',
    'patch.ps1',
    'diagnose.ps1',
    'workstation-manifest.json',
    'version.json'
)

$manifestPath = Join-Path $scriptRoot 'workstation-manifest.json'
$manifest = $null
$requiredTools = @{
    docker = '>=24.0.0'
    node   = '>=18.0.0'
    python = '>=3.11.0'
    git    = '>=2.40.0'
}

foreach ($file in $requiredFiles) {
    if (Test-Path (Join-Path $scriptRoot $file)) {
        Add-Check -Area 'workspace' -Name $file -Status 'ok' -Message 'Found.'
    }
    else {
        Add-Check -Area 'workspace' -Name $file -Status 'fail' -Message 'Missing required file.' -Recommendation 'Re-clone the repository before installing.'
    }
}

if (Test-Path $manifestPath) {
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        foreach ($property in $manifest.requiredTools.PSObject.Properties) {
            $requiredTools[$property.Name] = [string]$property.Value
        }
        Add-Check -Area 'workspace' -Name 'workstation-manifest.json' -Status 'ok' -Message 'Parsed successfully.'
    }
    catch {
        Add-Check -Area 'workspace' -Name 'workstation-manifest.json' -Status 'fail' -Message 'Could not parse JSON.' -Recommendation 'Fix or restore workstation-manifest.json before installing.'
    }
}

$isWindowsHost = $false
try {
    $isWindowsHost = [bool]$IsWindows
}
catch {
    $isWindowsHost = $env:OS -eq 'Windows_NT'
}

if ($isWindowsHost) {
    Add-Check -Area 'system' -Name 'OperatingSystem' -Status 'ok' -Message 'Windows detected.'
}
else {
    Add-Check -Area 'system' -Name 'OperatingSystem' -Status 'fail' -Message 'This probe is intended for Windows workstations.' -Recommendation 'Use a Windows 10/11 machine for the workstation install flow.'
}

$isAdmin = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch { }

if ($isAdmin) {
    Add-Check -Area 'system' -Name 'Administrator' -Status 'ok' -Message 'Shell is elevated.'
}
else {
    Add-Check -Area 'system' -Name 'Administrator' -Status 'warn' -Message 'Shell is not elevated.' -Recommendation 'Run setup.ps1 from an Administrator PowerShell session on a fresh machine.'
}

$psVersion = $PSVersionTable.PSVersion.ToString()
Add-Check -Area 'system' -Name 'PowerShell' -Status 'ok' -Message "PowerShell $psVersion"

try {
    $memoryBytes = [double](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $memoryGb = [Math]::Round($memoryBytes / 1GB, 1)
    if ($memoryGb -lt 8) {
        Add-Check -Area 'system' -Name 'Memory' -Status 'fail' -Message "$memoryGb GB RAM detected." -Recommendation 'Use a machine with at least 8 GB RAM; 16 GB is preferred.'
    }
    elseif ($memoryGb -lt 16) {
        Add-Check -Area 'system' -Name 'Memory' -Status 'warn' -Message "$memoryGb GB RAM detected." -Recommendation 'Usable, but 16 GB is the safer workstation target.'
    }
    else {
        Add-Check -Area 'system' -Name 'Memory' -Status 'ok' -Message "$memoryGb GB RAM detected."
    }
}
catch {
    Add-Check -Area 'system' -Name 'Memory' -Status 'warn' -Message 'Could not determine installed RAM.'
}

try {
    $repoDrive = (Get-Item $scriptRoot).PSDrive
    $repoDriveFreeGb = [Math]::Round($repoDrive.Free / 1GB, 1)
    if ($repoDriveFreeGb -lt 10) {
        Add-Check -Area 'system' -Name 'RepoDriveFreeSpace' -Status 'fail' -Message "$repoDriveFreeGb GB free on drive $($repoDrive.Name):" -Recommendation 'Free at least 10 GB before installation; 20 GB is preferred.'
    }
    elseif ($repoDriveFreeGb -lt 20) {
        Add-Check -Area 'system' -Name 'RepoDriveFreeSpace' -Status 'warn' -Message "$repoDriveFreeGb GB free on drive $($repoDrive.Name):" -Recommendation 'Installation may work, but 20 GB free is the safer target.'
    }
    else {
        Add-Check -Area 'system' -Name 'RepoDriveFreeSpace' -Status 'ok' -Message "$repoDriveFreeGb GB free on drive $($repoDrive.Name):"
    }
}
catch {
    Add-Check -Area 'system' -Name 'RepoDriveFreeSpace' -Status 'warn' -Message 'Could not determine free disk space.'
}

if (Test-Path 'D:\') {
    try {
        $dDrive = Get-PSDrive -Name 'D'
        $dFreeGb = [Math]::Round($dDrive.Free / 1GB, 1)
        if ($dFreeGb -lt 10) {
            Add-Check -Area 'system' -Name 'DDrive' -Status 'warn' -Message "D: exists but only has $dFreeGb GB free." -Recommendation 'Drive configuration may fall back to the repo drive.'
        }
        else {
            Add-Check -Area 'system' -Name 'DDrive' -Status 'ok' -Message "D: exists with $dFreeGb GB free."
        }
    }
    catch {
        Add-Check -Area 'system' -Name 'DDrive' -Status 'warn' -Message 'D: exists but free space could not be determined.'
    }
}
else {
    Add-Check -Area 'system' -Name 'DDrive' -Status 'warn' -Message 'D: drive not present.' -Recommendation 'This is acceptable; the installer will use the workspace drive instead.'
}

$wingetAvailable = Test-Command 'winget'
if ($wingetAvailable) {
    Add-Check -Area 'tooling' -Name 'winget' -Status 'ok' -Message 'winget is available.'
}
else {
    Add-Check -Area 'tooling' -Name 'winget' -Status 'warn' -Message 'winget is not available.' -Recommendation 'Missing auto-installable prerequisites will need to be installed manually.'
}

$toolResults = @{}

$toolDefinitions = @(
    @{ Name = 'docker'; Command = 'docker'; Args = @('--version'); Required = $requiredTools['docker']; AutoInstall = $true; HardMissing = $false },
    @{ Name = 'docker compose'; Command = 'docker'; Args = @('compose', 'version'); Required = $null; AutoInstall = $false; HardMissing = $true },
    @{ Name = 'node'; Command = 'node'; Args = @('--version'); Required = $requiredTools['node']; AutoInstall = $true; HardMissing = $false },
    @{ Name = 'npm'; Command = 'npm'; Args = @('--version'); Required = $null; AutoInstall = $false; HardMissing = $true },
    @{ Name = 'python'; Command = 'python'; Args = @('--version'); Required = $requiredTools['python']; AutoInstall = $false; HardMissing = $true },
    @{ Name = 'git'; Command = 'git'; Args = @('--version'); Required = $requiredTools['git']; AutoInstall = $true; HardMissing = $false }
)

foreach ($tool in $toolDefinitions) {
    $result = Invoke-ExternalCommand -Command $tool.Command -Arguments $tool.Args
    $detectedVersion = Get-FirstVersionString -Text $result.Output
    $requiredVersionString = Get-ConstraintVersion -Constraint $tool.Required
    $requiredVersion = Convert-ToComparableVersion -Value $requiredVersionString
    $actualVersion = Convert-ToComparableVersion -Value $detectedVersion
    $key = ($tool.Name -replace '\s+', '_')

    $toolResults[$key] = [pscustomobject]@{
        Installed = $result.Success
        Output = $result.Output
        Version = $detectedVersion
    }

    if (-not $result.Success) {
        if ($tool.AutoInstall -and $wingetAvailable) {
            Add-Check -Area 'tooling' -Name $tool.Name -Status 'warn' -Message 'Not installed.' -Recommendation 'setup.ps1 can install this prerequisite automatically.'
        }
        elseif ($tool.HardMissing -or -not $wingetAvailable) {
            Add-Check -Area 'tooling' -Name $tool.Name -Status 'fail' -Message 'Not installed.' -Recommendation "Install $($tool.Name) before running setup.ps1."
        }
        else {
            Add-Check -Area 'tooling' -Name $tool.Name -Status 'warn' -Message 'Not installed.'
        }
        continue
    }

    if ($requiredVersion -and $actualVersion -and $actualVersion -lt $requiredVersion) {
        Add-Check -Area 'tooling' -Name $tool.Name -Status 'fail' -Message "Version $detectedVersion is below required $requiredVersionString." -Recommendation "Upgrade $($tool.Name) manually before running setup.ps1."
        continue
    }

    if ($detectedVersion) {
        Add-Check -Area 'tooling' -Name $tool.Name -Status 'ok' -Message "Version $detectedVersion"
    }
    else {
        Add-Check -Area 'tooling' -Name $tool.Name -Status 'ok' -Message 'Installed.'
    }
}

$dockerDaemonReady = $false
if ($toolResults.ContainsKey('docker') -and $toolResults['docker'].Installed) {
    $dockerInfo = Invoke-ExternalCommand -Command 'docker' -Arguments @('info')
    if ($dockerInfo.Success) {
        $dockerDaemonReady = $true
        Add-Check -Area 'tooling' -Name 'docker-daemon' -Status 'ok' -Message 'Docker daemon is running.'
    }
    else {
        Add-Check -Area 'tooling' -Name 'docker-daemon' -Status 'fail' -Message 'Docker is installed but the daemon is not running.' -Recommendation 'Start Docker Desktop and wait for it to finish initializing.'
    }
}

$gitAvailable = $toolResults.ContainsKey('git') -and $toolResults['git'].Installed
$insideRepo = $false
$currentBranch = $null
$originUrl = $null
$expectedBranchLocal = $false
$expectedBranchRemote = $false
$worktreeDirty = $false

if ($gitAvailable) {
    $insideRepoResult = Invoke-ExternalCommand -Command 'git' -Arguments @('rev-parse', '--is-inside-work-tree')
    $insideRepo = $insideRepoResult.Success -and ($insideRepoResult.Output -eq 'true')

    if ($insideRepo) {
        Add-Check -Area 'git' -Name 'Repository' -Status 'ok' -Message 'Inside a git work tree.'

        $branchResult = Invoke-ExternalCommand -Command 'git' -Arguments @('branch', '--show-current')
        if ($branchResult.Success) {
            $currentBranch = $branchResult.Output.Trim()
        }

        if (-not $ExpectedBranch) {
            if ($currentBranch -and $currentBranch -in $autoDetectedDeploymentBranches) {
                $ExpectedBranch = $currentBranch
            }
            else {
                $ExpectedBranch = $defaultExpectedBranch
            }
        }

        $originResult = Invoke-ExternalCommand -Command 'git' -Arguments @('remote', 'get-url', 'origin')
        if ($originResult.Success -and $originResult.Output) {
            $originUrl = $originResult.Output.Trim()
            Add-Check -Area 'git' -Name 'origin' -Status 'ok' -Message $originUrl
        }
        else {
            Add-Check -Area 'git' -Name 'origin' -Status 'fail' -Message 'Remote origin is missing.' -Recommendation 'Set the origin remote before installing from this checkout.'
        }

        $statusResult = Invoke-ExternalCommand -Command 'git' -Arguments @('status', '--porcelain')
        if ($statusResult.Success) {
            $worktreeDirty = [bool]$statusResult.Output
            if ($worktreeDirty) {
                Add-Check -Area 'git' -Name 'Worktree' -Status 'warn' -Message 'Working tree has local changes.' -Recommendation 'A dirty worktree can block safe branch switching and patching.'
            }
            else {
                Add-Check -Area 'git' -Name 'Worktree' -Status 'ok' -Message 'Working tree is clean.'
            }
        }

        $localBranchCheck = Invoke-ExternalCommand -Command 'git' -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$ExpectedBranch")
        $expectedBranchLocal = $localBranchCheck.Success

        if ($originUrl) {
            $remoteBranchCheck = Invoke-ExternalCommand -Command 'git' -Arguments @('ls-remote', '--exit-code', '--heads', 'origin', $ExpectedBranch)
            $expectedBranchRemote = $remoteBranchCheck.Success
        }

        if ($expectedBranchLocal -or $expectedBranchRemote) {
            Add-Check -Area 'git' -Name 'ExpectedBranchAvailable' -Status 'ok' -Message "$ExpectedBranch is available." 
        }
        else {
            Add-Check -Area 'git' -Name 'ExpectedBranchAvailable' -Status 'fail' -Message "$ExpectedBranch is not available locally or on origin." -Recommendation 'Verify the target branch name before installing.'
        }

        if ($currentBranch -eq $ExpectedBranch) {
            Add-Check -Area 'git' -Name 'CurrentBranch' -Status 'ok' -Message "On $ExpectedBranch."
        }
        elseif ($currentBranch) {
            if ($worktreeDirty) {
                $switchRecommendation = if ($expectedBranchLocal) {
                    "Commit/stash local changes or use a fresh clone, then run: git switch $ExpectedBranch"
                }
                elseif ($expectedBranchRemote) {
                    "Commit/stash local changes or use a fresh clone, then run: git fetch origin; git switch --track origin/$ExpectedBranch"
                }
                else {
                    'Fix branch availability first.'
                }
            }
            else {
                $switchRecommendation = if ($expectedBranchLocal) {
                    "Run: git switch $ExpectedBranch"
                }
                elseif ($expectedBranchRemote) {
                    "Run: git fetch origin; git switch --track origin/$ExpectedBranch"
                }
                else {
                    'Fix branch availability first.'
                }
            }

            $branchStatus = if ($worktreeDirty) { 'fail' } else { 'warn' }
            $branchMessage = "Current branch is $currentBranch, expected $ExpectedBranch."
            Add-Check -Area 'git' -Name 'CurrentBranch' -Status $branchStatus -Message $branchMessage -Recommendation $switchRecommendation
        }
        else {
            Add-Check -Area 'git' -Name 'CurrentBranch' -Status 'warn' -Message 'Could not determine current branch.'
        }
    }
    else {
        Add-Check -Area 'git' -Name 'Repository' -Status 'fail' -Message 'This directory is not a git work tree.' -Recommendation 'Clone the repository before running the workstation installer.'
    }
}
else {
    Add-Check -Area 'git' -Name 'Repository' -Status 'fail' -Message 'Git is unavailable, so repo state could not be verified.' -Recommendation 'Install Git before using a repo-based workstation setup.'
}

if (-not $ExpectedBranch) {
    $ExpectedBranch = $defaultExpectedBranch
}

$serviceDirectories = @(
    'auth-service',
    'accounting-service',
    'flowise-proxy-service-py',
    'bridge',
    'flowise'
)

$envFilesPresent = @()
foreach ($directory in $serviceDirectories) {
    if (Test-Path (Join-Path $scriptRoot "$directory\.env")) {
        $envFilesPresent += $directory
    }
}

$localVersionExists = Test-Path (Join-Path $scriptRoot '.local-version')

$chatProxyContainers = @()
$dockerContainerNames = @()
if ($dockerDaemonReady) {
    $dockerPs = Invoke-ExternalCommand -Command 'docker' -Arguments @('ps', '--format', '{{.Names}}')
    if ($dockerPs.Success -and $dockerPs.Output) {
        $dockerContainerNames = @($dockerPs.Output -split "`r?`n" | Where-Object { $_ })
        $chatProxyContainers = @($dockerContainerNames | Where-Object {
            $_ -match 'auth-service|accounting-service|flowise-proxy|bridge|bridge-ui|^flowise$|mongodb-auth|mongodb-proxy|postgres-accounting|flowise-postgres'
        })
    }
}

$expectedPorts = @(3000, 3001, 3002, 3082, 8000, 27017)
$portUsage = Get-PortUsage -Ports $expectedPorts
$portConflicts = @()
foreach ($entry in $portUsage) {
    $isLikelyDockerProxy = $entry.ProcessName -match 'com\.docker|docker|vmmem|vpnkit|wslrelay'
    if (-not $isLikelyDockerProxy) {
        $portConflicts += $entry
    }
}

if ($localVersionExists) {
    Add-Check -Area 'state' -Name '.local-version' -Status 'warn' -Message 'Machine already has a local deployment marker.' -Recommendation 'This does not look like a fresh install target.'
}
else {
    Add-Check -Area 'state' -Name '.local-version' -Status 'ok' -Message 'No local deployment marker found.'
}

if ($chatProxyContainers.Count -gt 0) {
    Add-Check -Area 'state' -Name 'Containers' -Status 'warn' -Message "Found running ChatProxy-related containers: $($chatProxyContainers -join ', ')" -Recommendation 'Use diagnose.ps1 or patch.ps1 instead of a fresh setup on top of a live local deployment.'
}
else {
    Add-Check -Area 'state' -Name 'Containers' -Status 'ok' -Message 'No running ChatProxy containers detected.'
}

if ($envFilesPresent.Count -eq 0) {
    Add-Check -Area 'state' -Name '.env files' -Status 'ok' -Message 'No service .env files detected.'
}
elseif ($envFilesPresent.Count -eq $serviceDirectories.Count) {
    Add-Check -Area 'state' -Name '.env files' -Status 'warn' -Message 'All service .env files already exist.' -Recommendation 'This machine has already been prepared at least once; review before rerunning setup.ps1.'
}
else {
    Add-Check -Area 'state' -Name '.env files' -Status 'warn' -Message "Partial .env state detected for: $($envFilesPresent -join ', ')" -Recommendation 'Investigate partial local state before treating this as a fresh install.'
}

if ($portUsage.Count -eq 0) {
    Add-Check -Area 'state' -Name 'Ports' -Status 'ok' -Message 'Expected service ports are free.'
}
elseif ($portConflicts.Count -eq 0) {
    Add-Check -Area 'state' -Name 'Ports' -Status 'warn' -Message 'Expected service ports are already bound, likely by Docker-published services.' -Recommendation 'This also suggests the machine is not a fresh install target.'
}
else {
    $conflictSummary = $portConflicts | ForEach-Object {
        if ($_.ProcessName) {
            "$($_.Port):$($_.ProcessName)"
        }
        else {
            "$($_.Port):pid-$($_.ProcessId)"
        }
    }
    Add-Check -Area 'state' -Name 'Ports' -Status 'fail' -Message "Conflicting listeners detected on expected ports: $($conflictSummary -join ', ')" -Recommendation 'Stop or move conflicting services before installing ChatProxy.'
}

$allChecks = @($checks)

$statusGroups = @{
    workspace = @($allChecks | Where-Object Area -eq 'workspace')
    system    = @($allChecks | Where-Object Area -eq 'system')
    tooling   = @($allChecks | Where-Object Area -in @('tooling', 'git'))
    state     = @($allChecks | Where-Object Area -eq 'state')
}

$workspaceStatus = Get-WorstStatus -Statuses @($statusGroups.workspace.Status)
$systemStatus = Get-WorstStatus -Statuses @($statusGroups.system.Status)
$toolingStatus = Get-WorstStatus -Statuses @($statusGroups.tooling.Status)
$stateStatus = Get-WorstStatus -Statuses @($statusGroups.state.Status)

$existingInstall = $localVersionExists -or $chatProxyContainers.Count -gt 0
$partialInstall = (-not $existingInstall) -and (($envFilesPresent.Count -gt 0) -or ($portUsage.Count -gt 0))

$readyForSetup = (
    $workspaceStatus -eq 'ok' -and
    $systemStatus -ne 'fail' -and
    $toolingStatus -ne 'fail' -and
    $stateStatus -eq 'ok'
)

$missingInstallerManagedPrereqs = @()
foreach ($name in @('docker', 'node', 'git')) {
    $key = $name
    if ($toolResults.ContainsKey($key) -and -not $toolResults[$key].Installed) {
        $missingInstallerManagedPrereqs += $name
    }
}

$decisionAction = $null
$decisionReason = $null
$decisionCommand = $null
$decisionExitCode = 1

if ($existingInstall) {
    $decisionAction = 'existing-install'
    $decisionReason = 'This workstation already looks provisioned. Do not do a blind fresh install over local state.'
    $decisionCommand = '.\diagnose.ps1 -Quick'
    $decisionExitCode = 0
}
elseif ($partialInstall) {
    $decisionAction = 'partial-install'
    $decisionReason = 'The machine is not fresh, but it also does not look cleanly installed.'
    $decisionCommand = '.\diagnose.ps1'
}
elseif ($workspaceStatus -eq 'fail') {
    $decisionAction = 'fix-workspace'
    $decisionReason = 'The repository layout or branch state is not safe for installation yet.'
    $decisionCommand = if ($expectedBranchRemote -or $expectedBranchLocal) {
        "git fetch origin; git switch --track origin/$ExpectedBranch"
    }
    else {
        'Fix the repository checkout first.'
    }
}
elseif ($systemStatus -eq 'fail' -or $toolingStatus -eq 'fail') {
    $decisionAction = 'fix-blockers'
    $decisionReason = 'Manual blockers remain before a safe workstation install.'
    $decisionCommand = 'Install or start the missing prerequisites shown above, then rerun this probe.'
}
elseif ($missingInstallerManagedPrereqs.Count -gt 0) {
    $decisionAction = 'run-setup'
    $decisionReason = "setup.ps1 can install these missing prerequisites: $($missingInstallerManagedPrereqs -join ', ')."
    $decisionCommand = '.\setup.ps1'
    $decisionExitCode = 0
}
elseif ($readyForSetup) {
    $decisionAction = 'run-setup-skip-prereqs'
    $decisionReason = 'This machine looks like a clean target and the required tools are already in place.'
    $decisionCommand = '.\setup.ps1 -SkipPrereqs'
    $decisionExitCode = 0
}
else {
    $decisionAction = 'review-warnings'
    $decisionReason = 'No hard blocker was found, but warnings remain that should be reviewed before installation.'
    $decisionCommand = '.\setup.ps1'
}

$summary = [pscustomobject]@{
    ExpectedBranch       = $ExpectedBranch
    CurrentBranch        = $currentBranch
    OriginUrl            = $originUrl
    WorkspaceStatus      = $workspaceStatus
    SystemStatus         = $systemStatus
    ToolingStatus        = $toolingStatus
    LocalStateStatus     = $stateStatus
    ExistingInstall      = $existingInstall
    PartialInstall       = $partialInstall
    RecommendedAction    = $decisionAction
    RecommendedCommand   = $decisionCommand
    Reason               = $decisionReason
    ExitCode             = $decisionExitCode
}

$result = [pscustomobject]@{
    ProbedAtUtc = [DateTime]::UtcNow.ToString('s') + 'Z'
    Machine     = $env:COMPUTERNAME
    Workspace   = $scriptRoot
    Summary     = $summary
    Checks       = $allChecks
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
    exit $decisionExitCode
}

Write-Header

$areasInOrder = @('workspace', 'git', 'system', 'tooling', 'state')
foreach ($area in $areasInOrder) {
    $areaChecks = @($allChecks | Where-Object Area -eq $area)
    if ($areaChecks.Count -eq 0) {
        continue
    }

    Write-Host ""
    Write-Host "[$area]" -ForegroundColor Cyan
    foreach ($check in $areaChecks) {
        Write-CheckOutput -Check $check
    }
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Decision" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$decisionColor = switch ($decisionExitCode) {
    0 { 'Green' }
    default { 'Yellow' }
}

Write-Host "Action  : $decisionAction" -ForegroundColor $decisionColor
Write-Host "Reason  : $decisionReason" -ForegroundColor $decisionColor
Write-Host "Command : $decisionCommand" -ForegroundColor Cyan

if ($decisionAction -eq 'existing-install') {
    Write-Host "Next    : If health looks good, use .\patch.ps1 instead of rerunning setup.ps1." -ForegroundColor DarkGray
}
elseif ($decisionAction -eq 'run-setup') {
    Write-Host "Next    : setup.ps1 may install missing prerequisites, then prompt for a Docker restart before continuing." -ForegroundColor DarkGray
}
elseif ($decisionAction -eq 'run-setup-skip-prereqs') {
    Write-Host "Next    : After setup completes, run .\diagnose.ps1 -Quick." -ForegroundColor DarkGray
}

exit $decisionExitCode