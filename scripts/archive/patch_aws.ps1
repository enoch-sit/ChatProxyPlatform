#!/usr/bin/env pwsh
<#
.SYNOPSIS
AWS Patch Deployment & Monitoring Script

.DESCRIPTION
Automates AWS deployment verification, monitoring, and rollback for
dev/staging/prod environments.

.PARAMETER Environment
Target environment: dev, staging, prod

.PARAMETER Action
Deploy, Monitor, Rollback, Status

.PARAMETER Duration
Monitoring duration in minutes (default: 120)

.EXAMPLE
.\patch_aws.ps1 -Environment dev -Action Deploy
.\patch_aws.ps1 -Environment prod -Action Monitor -Duration 120
.\patch_aws.ps1 -Environment staging -Action Rollback
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory=$true)]
    [ValidateSet('Deploy', 'Monitor', 'Rollback', 'Status')]
    [string]$Action,

    [int]$Duration = 120,
    [string]$Region = "us-east-1",
    [string]$BaseUrl = ""
)

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

$logFile = "patch_aws_${Environment}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$clusterName = "chatproxy-$Environment-cluster"

function Resolve-BaseUrl {
    if ($BaseUrl) {
        return $BaseUrl.TrimEnd('/')
    }

    $endpoint = Get-ALBEndpoint
    if (-not $endpoint) {
        return $null
    }

    return "https://$endpoint"
}

function Write-Log {
    param([string]$Message, [ValidateSet('Info', 'Success', 'Warning', 'Error')]$Level = 'Info')
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = "[$timestamp] [$Level] $Message"
    
    Add-Content -Path $logFile -Value $output
    
    switch ($Level) {
        'Success' { Write-Host "✅ $Message" -ForegroundColor Green }
        'Warning' { Write-Host "⚠️  $Message" -ForegroundColor Yellow }
        'Error' { Write-Host "❌ $Message" -ForegroundColor Red }
        default { Write-Host "ℹ️  $Message" -ForegroundColor Cyan }
    }
}

function Get-ALBEndpoint {
    Write-Log "Retrieving ALB endpoint for $Environment..."

    # Try Terraform outputs first when environment folder exists.
    $envPath = "infra/environments/$Environment"
    if (Test-Path $envPath) {
        try {
            Push-Location $envPath

            $endpoint = terraform output -raw platform_alb_dns_name 2>$null
            if (-not $endpoint) {
                $endpoint = terraform output -raw alb_dns_name 2>$null
            }

            if ($endpoint) {
                Write-Log "ALB Endpoint: http://$endpoint" Success
                return $endpoint
            }
        }
        catch {
            Write-Log "Could not retrieve ALB endpoint from Terraform outputs: $_" Warning
        }
        finally {
            Pop-Location
        }
    }

    # Fallback: query AWS directly for active ALB matching environment naming.
    try {
        $dns = aws elbv2 describe-load-balancers `
            --region $Region `
            --query "LoadBalancers[?contains(LoadBalancerName, 'chatproxy-$Environment') && State.Code=='active']|[0].DNSName" `
            --output text

        if ($dns -and $dns -ne 'None') {
            Write-Log "ALB Endpoint (AWS fallback): http://$dns" Success
            return $dns
        }
    }
    catch {
        Write-Log "Could not retrieve ALB endpoint from AWS API: $_" Error
    }

    return $null
}

function Get-ServiceStatus {
    Write-Log "Checking ECS service status..."

    $statuses = @()

    try {
        $serviceArnsJson = aws ecs list-services `
            --cluster $clusterName `
            --region $Region `
            --output json

        $serviceArns = ($serviceArnsJson | ConvertFrom-Json).serviceArns
        if (-not $serviceArns -or $serviceArns.Count -eq 0) {
            Write-Log "  No services found in cluster $clusterName" Warning
            return $statuses
        }

        $serviceDetailsJson = aws ecs describe-services `
            --cluster $clusterName `
            --services $serviceArns `
            --region $Region `
            --output json

        $serviceDetails = ($serviceDetailsJson | ConvertFrom-Json).services
        $servicePatterns = @('auth', 'accounting', 'flowise-proxy', 'bridge')

        foreach ($pattern in $servicePatterns) {
            $svc = $serviceDetails | Where-Object { $_.serviceName -like "*$pattern*" } | Select-Object -First 1

            if ($svc) {
                Write-Log "  $($svc.serviceName) - Status: $($svc.status), Running: $($svc.runningCount)/$($svc.desiredCount)" Info
                $statuses += @{
                    Service = $svc.serviceName
                    Status  = $svc.status
                    Running = $svc.runningCount
                    Desired = $svc.desiredCount
                }
            }
            else {
                Write-Log "  No ECS service matched pattern '$pattern' in $clusterName" Warning
            }
        }
    }
    catch {
        Write-Log "  Error checking ECS services for cluster $clusterName : $_" Warning
    }

    return $statuses
}

function Get-HealthCheckStatus {
    Write-Log "Checking ALB target health..."
    
    try {
        $targetGroups = aws elbv2 describe-target-groups `
            --region $Region `
            --query "TargetGroups[?contains(TargetGroupArn, 'chatproxy-$Environment')].TargetGroupArn" `
            --output text
        
        if ($targetGroups) {
            foreach ($tg in $targetGroups -split '\s+') {
                if ($tg) {
                    $health = aws elbv2 describe-target-health `
                        --target-group-arn $tg `
                        --region $Region `
                        --query 'TargetHealthDescriptions[].TargetHealth.[State,Reason]' `
                        --output text
                    
                    $healthy = ($health -match 'healthy').Count
                    $unhealthy = ($health -match 'unhealthy').Count
                    
                    Write-Log "  Target Group: Healthy=$healthy, Unhealthy=$unhealthy" Info
                }
            }
        }
    }
    catch {
        Write-Log "Error checking target health: $_" Warning
    }
}

function Test-ServiceEndpoint {
    param([string]$ResolvedBaseUrl)
    
    Write-Log "Testing service endpoints at $ResolvedBaseUrl ..."

    $checks = @(
        @{ Name = 'Bridge UI'; Paths = @('/'); Accept = @(200, 301, 302) },
        @{ Name = 'Auth API'; Paths = @('/api/auth/health'); Accept = @(200) },
        @{ Name = 'Accounting API'; Paths = @('/api/accounting/health'); Accept = @(200) },
        @{ Name = 'Chat API'; Paths = @('/api/chat/health', '/api/v1/chat/health', '/health'); Accept = @(200) }
    )
    
    $allHealthy = $true
    
    foreach ($check in $checks) {
        $passed = $false
        $statuses = @()

        foreach ($path in $check.Paths) {
            $statusCode = $null
            try {
                $response = Invoke-WebRequest `
                    -UseBasicParsing `
                    -Uri "$ResolvedBaseUrl$path" `
                    -TimeoutSec 10 `
                    -MaximumRedirection 0 `
                    -ErrorAction Stop

                $statusCode = [int]$response.StatusCode
            }
            catch {
                if ($_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
            }

            if ($null -ne $statusCode) {
                $statuses += "$path=$statusCode"
                if ($check.Accept -contains $statusCode) {
                    $passed = $true
                    break
                }
            }
        }

        if ($passed) {
            Write-Log "  $($check.Name) - OK ($($statuses -join ', '))" Success
        } else {
            Write-Log "  $($check.Name) - FAILED ($($statuses -join ', '))" Error
            $allHealthy = $false
        }
    }
    
    return $allHealthy
}

function Get-CloudWatchMetrics {
    Write-Log "Retrieving CloudWatch metrics..."
    
    try {
        # Error Rate (5xx)
        $errorMetric = aws cloudwatch get-metric-statistics `
            --namespace AWS/ApplicationELB `
            --metric-name HTTPCode_Target_5XX_Count `
            --start-time (Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') `
            --end-time (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') `
            --period 900 `
            --statistics Sum `
            --region $Region `
            --query 'Datapoints[0].Sum' `
            --output text
        
        Write-Log "  5xx Error Count (15min): $errorMetric" Info
        
        # Response Time
        $latencyMetric = aws cloudwatch get-metric-statistics `
            --namespace AWS/ApplicationELB `
            --metric-name TargetResponseTime `
            --start-time (Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') `
            --end-time (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') `
            --period 900 `
            --statistics Average `
            --region $Region `
            --query 'Datapoints[0].Average' `
            --output text
        
        if ($latencyMetric -and $latencyMetric -ne 'None') {
            $latencyMs = ($latencyMetric * 1000) -as [int]
            Write-Log "  Avg Response Time: ${latencyMs}ms" Info
        }
        
        # Active Connections
        $connMetric = aws cloudwatch get-metric-statistics `
            --namespace AWS/ApplicationELB `
            --metric-name ActiveConnectionCount `
            --start-time (Get-Date).AddMinutes(-15).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') `
            --end-time (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') `
            --period 900 `
            --statistics Sum `
            --region $Region `
            --query 'Datapoints[0].Sum' `
            --output text
        
        Write-Log "  Active Connections: $connMetric" Info
    }
    catch {
        Write-Log "Error retrieving metrics: $_" Warning
    }
}

function Monitor-Deployment {
    Write-Log "=== MONITORING DEPLOYMENT ===" Info
    Write-Log "Environment: $Environment"
    Write-Log "Duration: $Duration minutes"
    Write-Log "Monitoring started at $(Get-Date)"
    
    $resolvedBaseUrl = Resolve-BaseUrl
    if (-not $resolvedBaseUrl) {
        Write-Log "Could not determine base URL - cannot monitor" Error
        return 1
    }
    
    $monitoringInterval = 300  # 5 minutes
    $iterations = [math]::Ceiling($Duration / 5)
    $issueCount = 0
    
    for ($i = 1; $i -le $iterations; $i++) {
        Write-Log "--- Monitoring Cycle $i/$iterations ---" Info
        
        # Get status
        Get-ServiceStatus | Out-Null
        Get-HealthCheckStatus
        
        # Test endpoints
        if (-not (Test-ServiceEndpoint -ResolvedBaseUrl $resolvedBaseUrl)) {
            $issueCount++
            Write-Log "Endpoint test FAILED - issue count: $issueCount" Warning
        }
        
        # Get metrics
        Get-CloudWatchMetrics
        
        # Check logs
        Write-Log "Checking recent error logs..."
        try {
            $startTimeMs = [DateTimeOffset]::UtcNow.AddMinutes(-5).ToUnixTimeMilliseconds()

            $errors = aws logs filter-log-events `
                --log-group-name "/chatproxy/$Environment/auth-service" `
                --start-time $startTimeMs `
                --filter-pattern 'ERROR' `
                --region $Region `
                --query 'events[].message' `
                --output text | Measure-Object -Line
            
            if ($errors.Lines -gt 0) {
                Write-Log "  Found $($errors.Lines) ERROR log entries in auth-service" Warning
            }
        }
        catch {
            Write-Log "  Error retrieving logs: $_" Warning
        }
        
        if ($i -lt $iterations) {
            Write-Log "Waiting $monitoringInterval seconds until next check..." Info
            Start-Sleep -Seconds $monitoringInterval
        }
    }
    
    Write-Log "=== MONITORING COMPLETE ===" Info
    
    if ($issueCount -gt 3) {
        Write-Log "ALERT: $issueCount endpoint failures detected - consider investigating" Error
        return 1
    }
    
    Write-Log "Monitoring completed successfully" Success
    return 0
}

function Invoke-Rollback {
    Write-Log "=== INITIATING ROLLBACK ===" Warning
    
    if ($Environment -eq 'prod') {
        Write-Log "Production rollback - requiring confirmation" Warning
        Write-Host "This will rollback production! Type 'YES-ROLLBACK-PROD' to confirm:"
        $confirm = Read-Host
        
        if ($confirm -ne 'YES-ROLLBACK-PROD') {
            Write-Log "Rollback cancelled" Warning
            return 1
        }
    }
    
    try {
        Write-Log "Reverting to previous Git commit..."
        
        # Find previous merge commit
        $commits = git log --oneline --decorate -20 | grep -i 'merge\|main'
        Write-Log "Recent commits:"
        Write-Log $commits
        
        Write-Host "Enter commit hash to rollback to (e.g., abc1234):"
        $rollbackCommit = Read-Host
        
        if (-not $rollbackCommit -or $rollbackCommit.Length -lt 7) {
            Write-Log "Invalid commit hash" Error
            return 1
        }
        
        # Create revert commit
        git revert -m 1 $rollbackCommit -n
        git commit -m "Rollback: Reverting to $rollbackCommit"
        git push origin release/aws
        
        Write-Log "Rollback commit pushed - GitHub Actions will redeploy" Success
        Write-Log "Monitor deployment: https://github.com/yourorg/yourrepo/actions" Info
        
        return 0
    }
    catch {
        Write-Log "Rollback failed: $_" Error
        return 1
    }
}

function Get-DeploymentStatus {
    Write-Log "=== DEPLOYMENT STATUS ===" Info
    Write-Log "Environment: $Environment"
    Write-Log "Cluster: $clusterName"
    Write-Log ""
    
    Get-ServiceStatus | Format-Table
    Write-Log ""
    
    Get-HealthCheckStatus
    Write-Log ""
    
    $resolvedBaseUrl = Resolve-BaseUrl
    if ($resolvedBaseUrl) {
        Write-Log "Testing endpoints..."
        Test-ServiceEndpoint -ResolvedBaseUrl $resolvedBaseUrl | Out-Null
    }
    
    Write-Log ""
    Get-CloudWatchMetrics
    
    return 0
}

# Main execution
Write-Log "AWS Patch Tool Started - Environment: $Environment, Action: $Action" Info

try {
    switch ($Action) {
        'Deploy' {
            Write-Log "Initiating deployment to $Environment..." Info
            Write-Log "Repository branch must be pushed before running this" Info
            Write-Log "Monitor GitHub Actions for build progress" Info
            Write-Log "Run 'patch_aws.ps1 -Environment $Environment -Action Monitor' after build completes" Info
            exit 0
        }
        'Monitor' {
            $exitCode = Monitor-Deployment
            exit $exitCode
        }
        'Rollback' {
            $exitCode = Invoke-Rollback
            exit $exitCode
        }
        'Status' {
            $exitCode = Get-DeploymentStatus
            exit $exitCode
        }
    }
}
catch {
    Write-Log "Fatal error: $_" Error
    exit 1
}
finally {
    Write-Log "Execution completed" Info
    Write-Log "Log file: $logFile" Info
}
