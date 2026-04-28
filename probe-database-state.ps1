#!/usr/bin/env pwsh
param()

$ErrorActionPreference = 'Continue'

function Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message"
}

Log "=== probe-database-state ==="

Log "Checking MongoDB container..."
$mongoPs = docker ps --filter "name=mongodb-auth" --format "{{.Names}} {{.Status}}" 2>&1
if ($LASTEXITCODE -ne 0 -or -not $mongoPs) {
    Log "MongoDB container not available: $mongoPs"
} else {
    Log "MongoDB container: $mongoPs"
    $mongoDbList = docker exec mongodb-auth mongosh --quiet --eval "db.adminCommand('listDatabases').databases.map(d => d.name).join(', ')" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log "MongoDB reachable. Databases: $mongoDbList"
    } else {
        Log "MongoDB query failed: $mongoDbList"
    }

    $mongoUserCount = docker exec mongodb-auth mongosh --quiet --eval "db = db.getSiblingDB('auth_db'); db.users.countDocuments()" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log "auth_db.users count: $mongoUserCount"
    } else {
        Log "auth_db user count query failed: $mongoUserCount"
    }
}

Log "Checking Postgres container..."
$pgPs = docker ps --filter "name=postgres-accounting" --format "{{.Names}} {{.Status}}" 2>&1
if ($LASTEXITCODE -ne 0 -or -not $pgPs) {
    Log "Postgres container not available: $pgPs"
} else {
    Log "Postgres container: $pgPs"
    $pgDb = docker exec postgres-accounting psql -U postgres -d accounting_db -t -A -c "select current_database();" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log "Postgres reachable. Current DB: $pgDb"
    } else {
        Log "Postgres query failed: $pgDb"
    }

    $pgTableCount = docker exec postgres-accounting psql -U postgres -d accounting_db -t -A -c "select count(*) from information_schema.tables where table_schema = 'public';" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log "Public table count: $pgTableCount"
    } else {
        Log "Postgres table count query failed: $pgTableCount"
    }
}

Log "=== probe complete ==="