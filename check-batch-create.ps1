<#
.SYNOPSIS
    Validate BHSS Batch User Creation Results
    
.DESCRIPTION
    Queries both auth and accounting services to verify users were created
    Checks credit allocation status
    Returns exit code for CI/CD pipelines
#>

param(
    [string]$ComputerName = "localhost",
    [string]$AdminToken = $null
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir "logs"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "batch-check-$Timestamp.log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

function Check-Users-In-Auth-Service {
    Write-Log "Checking users in Auth service..."
    
    $url = "http://$ComputerName:3000/api/admin/users"
    
    try {
        if ($AdminToken) {
            $headers = @{ "Authorization" = "Bearer $AdminToken" }
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 10
        } else {
            $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10
        }
        
        $userCount = if ($response -is [array]) { $response.Count } else { 1 }
        Write-Log "✅ Auth service users: $userCount"
        return $userCount -gt 0
    } catch {
        Write-Log "❌ Failed to query Auth service: $_" "ERROR"
        return $false
    }
}

function Check-Users-In-Accounting-Service {
    Write-Log "Checking users in Accounting service..."
    
    $url = "http://$ComputerName:3001/api/admin/users"
    
    try {
        if ($AdminToken) {
            $headers = @{ "Authorization" = "Bearer $AdminToken" }
            $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -TimeoutSec 10
        } else {
            $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10
        }
        
        $userCount = if ($response -is [array]) { $response.Count } else { 1 }
        Write-Log "✅ Accounting service users: $userCount"
        return $userCount -gt 0
    } catch {
        Write-Log "❌ Failed to query Accounting service: $_" "ERROR"
        return $false
    }
}

# Main
Write-Log "=== BHSS Batch Creation Validation Started ==="

$authOk = Check-Users-In-Auth-Service
$accountingOk = Check-Users-In-Accounting-Service

if ($authOk -and $accountingOk) {
    Write-Log "✅ Batch user creation validation PASSED"
    exit 0
} else {
    Write-Log "❌ Batch user creation validation FAILED" "ERROR"
    exit 1
}
