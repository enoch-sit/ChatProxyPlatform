<#
.SYNOPSIS
    Read-only AWS ECS deployment audit for ChatProxy environments.

.DESCRIPTION
    Compares the live ECS task definition image for each platform service with the
    expected image in infra/environments/<env>/terraform.tfvars, then layers on
    ECS stability, target group health, ECR image freshness, and recent log signals.

.EXAMPLE
    .\infra\scripts\audit-ecs-status.ps1

.EXAMPLE
    .\infra\scripts\audit-ecs-status.ps1 -Environment dev -AsJson
#>
[CmdletBinding()]
param(
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [string]$Region,

    [int]$LogWindowMinutes = 30,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serviceRegistry = @{
    "flowise-proxy" = @{
        TfVar     = "flowise_proxy_service_image"
        EcrRepo   = "chatproxy/flowise-proxy"
        EcsSuffix = "flowise-proxy-service"
    }
    "auth-service" = @{
        TfVar     = "auth_service_image"
        EcrRepo   = "chatproxy/auth-service"
        EcsSuffix = "auth-service"
    }
    "accounting-service" = @{
        TfVar     = "accounting_service_image"
        EcrRepo   = "chatproxy/accounting-service"
        EcsSuffix = "accounting-service"
    }
    "bridge" = @{
        TfVar     = "bridge_image"
        EcrRepo   = "chatproxy/bridge"
        EcsSuffix = "bridge"
    }
}

function Invoke-AwsJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & aws @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "AWS CLI failed: aws $($Arguments -join ' ')`n$message"
    }

    $raw = ($output | Out-String).Trim()
    if (-not $raw) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Invoke-AwsText {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & aws @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $message = ($output | Out-String).Trim()
        throw "AWS CLI failed: aws $($Arguments -join ' ')`n$message"
    }

    return ($output | Out-String).Trim()
}

function Get-TfvarsAssignments {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $assignments = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"\s*$') {
            $assignments[$matches[1]] = $matches[2]
        }
    }

    return $assignments
}

function Get-ImageTag {
    param([string]$ImageUri)

    if (-not $ImageUri) {
        return $null
    }

    if ($ImageUri.Contains('@')) {
        return $null
    }

    $segments = $ImageUri.Split(':')
    if ($segments.Count -lt 2) {
        return $null
    }

    return $segments[-1]
}

function Get-ImageVersion {
    param([string]$ImageTag)

    if (-not $ImageTag) {
        return $null
    }

    if ($ImageTag -match '^v(?<version>\d+\.\d+\.\d+)') {
        return $matches['version']
    }

    return $null
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$tfvarsPath = Join-Path $repoRoot "infra\environments\$Environment\terraform.tfvars"
$versionPath = Join-Path $repoRoot 'version.json'

if (-not (Test-Path $tfvarsPath)) {
    throw "terraform.tfvars not found: $tfvarsPath"
}

if (-not (Test-Path $versionPath)) {
    throw "version.json not found: $versionPath"
}

$tfvars = Get-TfvarsAssignments -Path $tfvarsPath
$versionData = Get-Content $versionPath -Raw | ConvertFrom-Json

if (-not $Region) {
    if ($tfvars.ContainsKey('aws_region')) {
        $Region = $tfvars['aws_region']
    } else {
        $Region = Invoke-AwsText -Arguments @('configure', 'get', 'region')
    }
}

if (-not $Region) {
    $Region = 'us-east-1'
}

$accountId = if ($tfvars.ContainsKey('aws_account_id')) {
    $tfvars['aws_account_id']
} else {
    Invoke-AwsText -Arguments @('sts', 'get-caller-identity', '--query', 'Account', '--output', 'text')
}

$identityArn = Invoke-AwsText -Arguments @('sts', 'get-caller-identity', '--query', 'Arn', '--output', 'text')
$clusterName = "chatproxy-$Environment-cluster"
$logStartTime = [DateTimeOffset]::UtcNow.AddMinutes(-1 * $LogWindowMinutes).ToUnixTimeMilliseconds()

$results = foreach ($serviceName in $serviceRegistry.Keys) {
    $config = $serviceRegistry[$serviceName]
    $ecsServiceName = "chatproxy-$Environment-$($config.EcsSuffix)"
    $expectedImage = if ($tfvars.ContainsKey($config.TfVar)) { $tfvars[$config.TfVar] } else { $null }
    $expectedTag = Get-ImageTag -ImageUri $expectedImage
    $expectedVersion = Get-ImageVersion -ImageTag $expectedTag

    $serviceResponse = Invoke-AwsJson -Arguments @(
        'ecs', 'describe-services',
        '--cluster', $clusterName,
        '--services', $ecsServiceName,
        '--region', $Region,
        '--output', 'json'
    )

    $serviceInfo = $serviceResponse.services[0]
    $serviceFailures = @($serviceResponse.failures)
    if (-not $serviceInfo) {
        $failureReason = if ($serviceFailures.Count -gt 0) { $serviceFailures[0].reason } else { 'service-not-found' }
        [pscustomobject]@{
            Environment          = $Environment
            Cluster              = $clusterName
            Service              = $serviceName
            EcsService           = $ecsServiceName
            ExpectedImage        = $expectedImage
            ExpectedVersion      = $expectedVersion
            LiveImage            = $null
            LiveTag              = $null
            LiveVersion          = $null
            TaskDefinition       = $null
            DesiredCount         = $null
            RunningCount         = $null
            RolloutState         = $null
            TargetHealth         = 'unknown'
            LogSignal            = 'unknown'
            NewerImageInEcr      = $false
            DeployedPushedAt     = $null
            LatestEcrPushedAt    = $null
            LatestDeploymentNote = $failureReason
            Status               = 'drifted'
            Summary              = 'Service not found in ECS.'
        }
        continue
    }

    $taskDefinitionArn = $serviceInfo.taskDefinition
    $taskDefinitionResponse = Invoke-AwsJson -Arguments @(
        'ecs', 'describe-task-definition',
        '--task-definition', $taskDefinitionArn,
        '--region', $Region,
        '--output', 'json'
    )

    $containerDefinition = @($taskDefinitionResponse.taskDefinition.containerDefinitions)[0]
    $liveImage = $containerDefinition.image
    $liveTag = Get-ImageTag -ImageUri $liveImage
    $liveVersion = Get-ImageVersion -ImageTag $liveTag

    $primaryDeployment = @($serviceInfo.deployments | Where-Object { $_.status -eq 'PRIMARY' })[0]
    $rolloutState = if ($primaryDeployment) { $primaryDeployment.rolloutState } else { $null }
    $latestEvent = @($serviceInfo.events)[0]
    $latestEventMessage = if ($latestEvent) { $latestEvent.message } else { 'No recent ECS events.' }

    $targetHealthStates = @()
    foreach ($loadBalancer in @($serviceInfo.loadBalancers)) {
        $targetHealthResponse = Invoke-AwsJson -Arguments @(
            'elbv2', 'describe-target-health',
            '--target-group-arn', $loadBalancer.targetGroupArn,
            '--region', $Region,
            '--output', 'json'
        )

        foreach ($targetHealthDescription in @($targetHealthResponse.TargetHealthDescriptions)) {
            if ($targetHealthDescription.TargetHealth.state) {
                $targetHealthStates += $targetHealthDescription.TargetHealth.state
            }
        }
    }

    if ($targetHealthStates.Count -eq 0) {
        $targetHealthSummary = 'unknown'
        $allTargetsHealthy = $false
    } else {
        $uniqueStates = @($targetHealthStates | Sort-Object -Unique)
        $targetHealthSummary = $uniqueStates -join ','
        $allTargetsHealthy = ($uniqueStates.Count -eq 1 -and $uniqueStates[0] -eq 'healthy')
    }

    $logGroup = $null
    if ($containerDefinition.logConfiguration -and $containerDefinition.logConfiguration.options) {
        $logGroup = $containerDefinition.logConfiguration.options.'awslogs-group'
    }

    $logSignal = 'not-configured'
    if ($logGroup) {
        $logResponse = Invoke-AwsJson -Arguments @(
            'logs', 'filter-log-events',
            '--log-group-name', $logGroup,
            '--start-time', "$logStartTime",
            '--limit', '25',
            '--region', $Region,
            '--output', 'json'
        )

        $errorEvents = @($logResponse.events | Where-Object {
            $_.message -match '(?i)\b(error|exception|traceback|fatal|critical)\b'
        })

        if ($errorEvents.Count -gt 0) {
            $logSignal = "recent-errors:$($errorEvents.Count)"
        } else {
            $logSignal = 'clean'
        }
    }

    $imageDetails = Invoke-AwsJson -Arguments @(
        'ecr', 'describe-images',
        '--repository-name', $config.EcrRepo,
        '--region', $Region,
        '--output', 'json'
    )

    $imageDetailsList = @($imageDetails.imageDetails)
    $deployedImageDetail = $null
    if ($liveTag) {
        $deployedImageDetail = @($imageDetailsList | Where-Object {
            $imageTagsProperty = $_.PSObject.Properties['imageTags']
            $imageTagsProperty -and @($imageTagsProperty.Value) -contains $liveTag
        } | Sort-Object imagePushedAt -Descending)[0]
    }

    $latestImageDetail = @($imageDetailsList | Sort-Object imagePushedAt -Descending)[0]
    $deployedPushedAt = if ($deployedImageDetail) { [DateTimeOffset]$deployedImageDetail.imagePushedAt } else { $null }
    $latestEcrPushedAt = if ($latestImageDetail) { [DateTimeOffset]$latestImageDetail.imagePushedAt } else { $null }
    $newerImageInEcr = $false
    if ($deployedPushedAt -and $latestEcrPushedAt) {
        $newerImageInEcr = $latestEcrPushedAt.UtcDateTime -gt $deployedPushedAt.UtcDateTime
    }

    $serviceHealthy = (
        $serviceInfo.status -eq 'ACTIVE' -and
        $serviceInfo.runningCount -eq $serviceInfo.desiredCount -and
        $serviceInfo.desiredCount -ge 1 -and
        $rolloutState -eq 'COMPLETED' -and
        $allTargetsHealthy -and
        $logSignal -notlike 'recent-errors:*'
    )

    $status = if (-not $serviceHealthy) {
        'unhealthy'
    } elseif (-not $expectedImage -or $expectedImage -ne $liveImage) {
        'drifted'
    } elseif ($newerImageInEcr) {
        'behind'
    } else {
        'current'
    }

    $summary = switch ($status) {
        'current' { 'Live ECS image matches terraform.tfvars and health checks passed.' }
        'behind' { 'Live ECS image matches terraform.tfvars, but ECR has a newer pushed image.' }
        'drifted' { 'Live ECS image does not match terraform.tfvars.' }
        'unhealthy' { 'Deployment health checks failed or showed recent runtime errors.' }
    }

    [pscustomobject]@{
        Environment          = $Environment
        Cluster              = $clusterName
        Service              = $serviceName
        EcsService           = $ecsServiceName
        ExpectedImage        = $expectedImage
        ExpectedVersion      = $expectedVersion
        LiveImage            = $liveImage
        LiveTag              = $liveTag
        LiveVersion          = $liveVersion
        TaskDefinition       = $taskDefinitionArn
        DesiredCount         = $serviceInfo.desiredCount
        RunningCount         = $serviceInfo.runningCount
        RolloutState         = $rolloutState
        TargetHealth         = $targetHealthSummary
        LogSignal            = $logSignal
        NewerImageInEcr      = $newerImageInEcr
        DeployedPushedAt     = if ($deployedPushedAt) { $deployedPushedAt.UtcDateTime.ToString('s') + 'Z' } else { $null }
        LatestEcrPushedAt    = if ($latestEcrPushedAt) { $latestEcrPushedAt.UtcDateTime.ToString('s') + 'Z' } else { $null }
        LatestDeploymentNote = $latestEventMessage
        Status               = $status
        Summary              = $summary
    }
}

$output = [pscustomobject]@{
    Environment   = $Environment
    Region        = $Region
    AccountId     = $accountId
    CallerArn     = $identityArn
    VersionSource = $versionData.lastUpdated
    AuditedAtUtc  = [DateTime]::UtcNow.ToString('s') + 'Z'
    Results       = $results
}

if ($AsJson) {
    $output | ConvertTo-Json -Depth 6
    return
}

Write-Host "`nAWS ECS deployment audit" -ForegroundColor Cyan
Write-Host "Environment : $Environment" -ForegroundColor Cyan
Write-Host "Region      : $Region" -ForegroundColor Cyan
Write-Host "Account     : $accountId" -ForegroundColor Cyan
Write-Host "Caller      : $identityArn" -ForegroundColor Cyan

$results |
    Sort-Object Service |
    Select-Object Service, Status, ExpectedVersion, LiveVersion, DesiredCount, RunningCount, RolloutState, TargetHealth, LogSignal, NewerImageInEcr |
    Format-Table -AutoSize

Write-Host "`nService details" -ForegroundColor Cyan
foreach ($result in $results | Sort-Object Service) {
    Write-Host "`n[$($result.Service)] $($result.Status)" -ForegroundColor Yellow
    Write-Host "  Expected image : $($result.ExpectedImage)"
    Write-Host "  Live image     : $($result.LiveImage)"
    Write-Host "  Task definition: $($result.TaskDefinition)"
    Write-Host "  ECS counts     : running=$($result.RunningCount) desired=$($result.DesiredCount) rollout=$($result.RolloutState)"
    Write-Host "  Target health  : $($result.TargetHealth)"
    Write-Host "  Log signal     : $($result.LogSignal)"
    Write-Host "  Latest event   : $($result.LatestDeploymentNote)"
    Write-Host "  Summary        : $($result.Summary)"
}