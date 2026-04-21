<#
.SYNOPSIS
    BHSS Batch User Creation Wrapper
    Orchestrates batch user creation via Python script with BHSS config
    
.DESCRIPTION
    Sets environment variables and runs quickAddCredit_BHSS.py
    Integrates with fleet.ps1 for multi-machine deployment
    
.PARAMETER ComputerName
    Target BHSS machine (default: localhost)
    
.PARAMETER BatchUsers
    JSON file with user list (optional, uses default if not provided)
    
.PARAMETER AdminPassword
    Admin user password (from $env or default)
#>

param(
    [string]$ComputerName = "localhost",
    [string]$BatchUsers = $null,
    [string]$AdminPassword = $null
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $ScriptDir "logs"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "batch-create-$Timestamp.log"

# Create log directory if needed
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

function Validate-BHSS-Config {
    Write-Log "Validating BHSS configuration..."
    
    # Check if BHSS domain is reachable
    try {
        $result = Test-NetConnection -ComputerName $ComputerName -Port 3000 -WarningAction SilentlyContinue
        if ($result.TcpTestSucceeded) {
            Write-Log "✅ Auth service reachable at $ComputerName:3000"
            return $true
        } else {
            Write-Log "❌ Auth service unreachable at $ComputerName:3000" "ERROR"
            return $false
        }
    } catch {
        Write-Log "❌ Connection validation failed: $_" "ERROR"
        return $false
    }
}

function Run-Batch-Creation {
    Write-Log "Starting batch user creation..."
    
    # Set environment variables
    $env:AUTH_SERVICE_URL = "http://$ComputerName:3000"
    $env:ACCOUNT_SERVICE_URL = "http://$ComputerName:3001"
    $env:BATCH_ENV = "bhss"
    
    if ($AdminPassword) {
        $env:ADMIN_PASSWORD = $AdminPassword
    }
    
    Write-Log "Environment: AUTH_SERVICE_URL=$($env:AUTH_SERVICE_URL)"
    Write-Log "Environment: ACCOUNT_SERVICE_URL=$($env:ACCOUNT_SERVICE_URL)"
    
    # Run Python batch script
    $pythonScript = Join-Path $ScriptDir "accounting-service\quickManageCreditBatch\quickAddCredit_BHSS.py"
    
    if (-not (Test-Path $pythonScript)) {
        Write-Log "❌ Python script not found: $pythonScript" "ERROR"
        return $false
    }
    
    try {
        $output = & python $pythonScript 2>&1
        Write-Log $output
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "✅ Batch user creation completed successfully"
            return $true
        } else {
            Write-Log "❌ Batch user creation failed with exit code: $LASTEXITCODE" "ERROR"
            return $false
        }
    } catch {
        Write-Log "❌ Error executing batch creation: $_" "ERROR"
        return $false
    }
}

# Main execution
Write-Log "=== BHSS Batch User Creation Started ==="
Write-Log "Target: $ComputerName"
Write-Log "Log: $LogFile"

if (-not (Validate-BHSS-Config)) {
    Write-Log "❌ BHSS configuration validation failed. Exiting." "ERROR"
    exit 1
}

if (-not (Run-Batch-Creation)) {
    Write-Log "❌ Batch user creation failed" "ERROR"
    exit 1
}

Write-Log "=== BHSS Batch User Creation Completed ==="
exit 0
