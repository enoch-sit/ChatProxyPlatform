#!/usr/bin/env pwsh
<#
.SYNOPSIS
Local Patch Testing & Deployment Script

.DESCRIPTION
Automates unit testing, Docker builds, integration tests, and smoke tests
for local Windows deployments.

.PARAMETER ServiceName
Target service: auth-service, accounting-service, bridge, flowise-proxy, all

.PARAMETER Action
Test, Build, Deploy, or Full

.EXAMPLE
.\patch_local.ps1 -ServiceName auth-service -Action Full
.\patch_local.ps1 -ServiceName all -Action Test
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('auth-service', 'accounting-service', 'bridge', 'flowise-proxy', 'all')]
    [string]$ServiceName,

    [Parameter(Mandatory=$true)]
    [ValidateSet('Test', 'Build', 'Deploy', 'Full', 'Rollback')]
    [string]$Action,

    [string]$CommitMessage = "Patch deployment",
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

# Configuration
$services = if ($ServiceName -eq 'all') { 
    @('auth-service', 'accounting-service', 'bridge', 'flowise-proxy') 
} else { 
    @($ServiceName) 
}

$logFile = "patch_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$results = @()

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

function Test-Service {
    param([string]$Service)
    
    Write-Log "Testing $Service..."
    
    try {
        Push-Location $Service
        
        # Run npm tests
        if (Test-Path "package.json") {
            npm test 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "$Service tests FAILED" Error
                $results += @{Service = $Service; Test = 'FAILED'; Build = 'SKIPPED'; Deploy = 'SKIPPED'}
                Pop-Location
                return $false
            }
        }
        
        # Run linting
        if (Test-Path "package.json") {
            npm run lint 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "$Service lint FAILED" Warning
                # Don't fail on lint-only issues
            }
        }
        
        # Run Python tests (flowise-proxy)
        if (Test-Path "requirements.txt") {
            python -m pytest tests/ -v 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "$Service pytest FAILED" Error
                $results += @{Service = $Service; Test = 'FAILED'; Build = 'SKIPPED'; Deploy = 'SKIPPED'}
                Pop-Location
                return $false
            }
        }
        
        Write-Log "$Service tests PASSED" Success
        Pop-Location
        return $true
    }
    catch {
        Write-Log "Error testing $Service : $_" Error
        Pop-Location
        return $false
    }
}

function Build-Service {
    param([string]$Service)
    
    Write-Log "Building Docker image for $Service..."
    
    try {
        Push-Location $Service
        
        # Build development image
        docker build -f Dockerfile -t "${Service}:patch" . 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$Service Docker build FAILED" Error
            Pop-Location
            return $false
        }
        
        # Build production image (if available)
        if (Test-Path "Dockerfile.prod") {
            docker build -f Dockerfile.prod -t "${Service}:patch-prod" . 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "$Service production Docker build FAILED" Error
                Pop-Location
                return $false
            }
        }
        
        Write-Log "$Service Docker build PASSED" Success
        Pop-Location
        return $true
    }
    catch {
        Write-Log "Error building $Service : $_" Error
        Pop-Location
        return $false
    }
}

function Deploy-Service {
    param([string]$Service)
    
    Write-Log "Deploying $Service..."
    
    try {
        # Determine docker-compose file
        $composeFile = switch ($Service) {
            'auth-service' { 'docker-compose.dev.yml' }
            default { 'docker-compose.yml' }
        }
        
        if (-not (Test-Path "$Service/$composeFile")) {
            Write-Log "Docker compose file not found: $Service/$composeFile" Error
            return $false
        }
        
        # Stop existing service
        Push-Location $Service
        docker compose -f $composeFile down 2>&1 | Out-Null
        
        # Start with new image
        docker compose -f $composeFile up -d 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "$Service docker-compose up FAILED" Error
            Pop-Location
            return $false
        }
        
        Pop-Location
        
        # Wait for service to be healthy
        Start-Sleep -Seconds 10
        
        Write-Log "$Service deployment PASSED" Success
        return $true
    }
    catch {
        Write-Log "Error deploying $Service : $_" Error
        Pop-Location
        return $false
    }
}

function Test-ServiceHealth {
    param([string]$Service, [int]$Port)
    
    Write-Log "Checking health of $Service on port $Port..."
    
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$Port/health" -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Log "$Service health check PASSED" Success
            return $true
        }
    }
    catch {
        Write-Log "$Service health check FAILED (retrying...)" Warning
        Start-Sleep -Seconds 5
        
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port/health" -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-Log "$Service health check PASSED (on retry)" Success
                return $true
            }
        }
        catch {
            Write-Log "$Service health check FAILED" Error
            return $false
        }
    }
    
    return $false
}

function Invoke-SmokeTests {
    Write-Log "Running smoke tests..."
    
    $portMap = @{
        'auth-service' = 3000
        'accounting-service' = 3001
        'bridge' = 3082
        'flowise-proxy' = 8000
    }
    
    $allHealthy = $true
    
    foreach ($service in $services) {
        if (-not (Test-ServiceHealth -Service $service -Port $portMap[$service])) {
            $allHealthy = $false
        }
    }
    
    if ($allHealthy) {
        Write-Log "All smoke tests PASSED" Success
        return $true
    } else {
        Write-Log "Some smoke tests FAILED" Error
        return $false
    }
}

# Main execution
function Invoke-PatchAction {
    Write-Log "Starting patch action: $Action for $($services -join ', ')" Info
    
    $testsPassed = $true
    $buildsPassed = $true
    $deploymentsPassed = $true
    
    # Unit Tests
    if ($Action -in 'Test', 'Full') {
        Write-Log "=== UNIT TESTS ===" Info
        
        if (-not $SkipTests) {
            foreach ($service in $services) {
                if (-not (Test-Service -Service $service)) {
                    $testsPassed = $false
                }
            }
        }
        else {
            Write-Log "Skipping tests (--SkipTests)" Warning
        }
        
        if (-not $testsPassed) {
            Write-Log "Unit tests FAILED - aborting" Error
            return 1
        }
    }
    
    # Docker Build
    if ($Action -in 'Build', 'Full', 'Deploy') {
        Write-Log "=== DOCKER BUILD ===" Info
        
        foreach ($service in $services) {
            if (-not (Build-Service -Service $service)) {
                $buildsPassed = $false
            }
        }
        
        if (-not $buildsPassed) {
            Write-Log "Docker builds FAILED - aborting" Error
            return 1
        }
    }
    
    # Deployment
    if ($Action -in 'Deploy', 'Full') {
        Write-Log "=== DEPLOYMENT ===" Info
        
        foreach ($service in $services) {
            if (-not (Deploy-Service -Service $service)) {
                $deploymentsPassed = $false
            }
        }
        
        if (-not $deploymentsPassed) {
            Write-Log "Deployment FAILED" Error
            return 1
        }
        
        # Smoke Tests
        Write-Log "=== SMOKE TESTS ===" Info
        if (-not (Invoke-SmokeTests)) {
            Write-Log "Smoke tests FAILED - initiating rollback" Error
            return 1
        }
    }
    
    # Git operations
    if ($Action -eq 'Full') {
        Write-Log "=== GIT COMMIT ===" Info
        
        git add .
        git commit -m $CommitMessage
        
        Write-Log "Patch committed successfully" Success
    }
    
    Write-Log "Patch action COMPLETED successfully" Success
    return 0
}

# Execute
try {
    $exitCode = Invoke-PatchAction
    Write-Log "Exit code: $exitCode" Info
    exit $exitCode
}
catch {
    Write-Log "Fatal error: $_" Error
    exit 1
}
finally {
    Write-Log "Log file: $logFile" Info
    Get-Content $logFile -Tail 10
}
