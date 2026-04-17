<#
.SYNOPSIS
    One-time setup: AWS Budget alarm + ECR lifecycle policies for cost control.

.DESCRIPTION
    1. Creates a $150/month AWS Budget with 80% email alert
    2. Sets ECR lifecycle policies to keep only the last 5 images per repo

.EXAMPLE
    .\infra\scripts\dev-cost-guardrails.ps1 -AlertEmail your@email.com
#>

param(
    [Parameter(Mandatory)]
    [string]$AlertEmail,

    [string]$Region = "us-east-1",
    [int]$BudgetAmount = 150,
    [int]$AlertThreshold = 80,
    [int]$KeepImageCount = 5
)

$ErrorActionPreference = "Stop"
$AccountId = "168437900315"

# ── AWS Budget ─────────────────────────────────────────────────
Write-Host "`n=== Creating AWS Budget: `$$BudgetAmount/month ===" -ForegroundColor Yellow

$budgetJson = @"
{
    "BudgetName": "chatproxy-dev-monthly",
    "BudgetLimit": {
        "Amount": "$BudgetAmount",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {},
    "CostTypes": {
        "IncludeTax": true,
        "IncludeSubscription": true,
        "UseBlended": false,
        "IncludeRefund": false,
        "IncludeCredit": false,
        "IncludeUpfront": true,
        "IncludeRecurring": true,
        "IncludeOtherSubscription": true,
        "IncludeSupport": true,
        "IncludeDiscount": true,
        "UseAmortized": false
    }
}
"@

$notificationJson = @"
[
    {
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": $AlertThreshold,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "EMAIL",
                "Address": "$AlertEmail"
            }
        ]
    }
]
"@

$budgetFile = [System.IO.Path]::GetTempFileName()
$notifFile  = [System.IO.Path]::GetTempFileName()

try {
    $budgetJson | Set-Content -Path $budgetFile -Encoding UTF8
    $notificationJson | Set-Content -Path $notifFile -Encoding UTF8

    aws budgets create-budget `
        --account-id $AccountId `
        --budget "file://$budgetFile" `
        --notifications-with-subscribers "file://$notifFile" `
        --no-cli-pager 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Budget created: `$$BudgetAmount/month, alert at ${AlertThreshold}%" -ForegroundColor Green
    } else {
        Write-Host "  Budget may already exist (or error). Check AWS Console." -ForegroundColor DarkYellow
    }
} finally {
    Remove-Item $budgetFile, $notifFile -ErrorAction SilentlyContinue
}

# ── ECR Lifecycle Policies ─────────────────────────────────────
Write-Host "`n=== Setting ECR lifecycle policies (keep last $KeepImageCount images) ===" -ForegroundColor Yellow

$repos = @(
    "chatproxy/auth-service",
    "chatproxy/accounting-service",
    "chatproxy/flowise-proxy",
    "chatproxy/bridge"
)

$lifecyclePolicy = @"
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last $KeepImageCount images",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": $KeepImageCount
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
"@

foreach ($repo in $repos) {
    Write-Host "  $repo ..." -NoNewline
    aws ecr put-lifecycle-policy `
        --repository-name $repo `
        --lifecycle-policy-text $lifecyclePolicy `
        --region $Region `
        --no-cli-pager | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host " done" -ForegroundColor Green
    } else {
        Write-Host " failed" -ForegroundColor Red
    }
}

Write-Host "`n=== Cost guardrails configured ===" -ForegroundColor Cyan
Write-Host "Budget: `$$BudgetAmount/month with ${AlertThreshold}% alert to $AlertEmail" -ForegroundColor Cyan
Write-Host "ECR: keeping last $KeepImageCount images per repo" -ForegroundColor Cyan
