# Diagnostic and repair script for user admin roles
# Usage: ./check_admin_role.ps1 -Username "admin" -FixRole

param(
    [string]$Username = "admin",
    [switch]$FixRole = $false
)

$ErrorActionPreference = "Stop"

# Colors for output
$greenCheck = "✅"
$redX = "❌"
$blue = "`e[34m"
$yellow = "`e[33m"
$reset = "`e[0m"

Write-Host "`n$blue=== Auth Service User Role Diagnostic ===$reset`n"

# Step 1: Check if MongoDB is accessible
Write-Host "📌 Checking MongoDB connection..."
try {
    # Try to get MongoDB from Docker or local
    $mongoCmd = "mongosh"
    $mongoAvailable = Get-Command $mongoCmd -ErrorAction SilentlyContinue
    
    if (-not $mongoAvailable) {
        Write-Host "$redX MongoDB CLI not found. Checking via Docker..."
        
        # Try docker exec
        $containers = docker ps --filter "name=mongodb" --format "{{.Names}}" 2>$null
        if ($containers) {
            $container = $containers[0]
            Write-Host "$greenCheck Found MongoDB container: $container"
            Write-Host "`n$yellow Note: Use docker exec to query, or connect directly if available locally`n"
        } else {
            Write-Host "$redX No MongoDB container found"
            Write-Host "Run the following MongoDB query manually to check role:`n"
            Write-Host "  db.users.findOne({username: '$Username'}, {username: 1, email: 1, role: 1})`n"
            exit 0
        }
    }
    
} catch {
    Write-Host "$redX Error checking MongoDB: $_"
    exit 1
}

# Step 2: Query user via mongosh
Write-Host "🔍 Querying user: $Username`n"

$query = @"
db.users.findOne({username: '$Username'}, {username: 1, email: 1, role: 1, createdAt: 1, isVerified: 1})
"@

try {
    if ($mongoAvailable) {
        # Direct mongosh connection
        Write-Host "Executing query directly..."
        $result = mongosh --quiet --eval $query 2>&1 | Out-String
        Write-Host "Result: $result"
    } else {
        # Docker exec
        Write-Host "Executing via Docker..."
        $result = docker exec $container mongosh --quiet --eval $query 2>&1 | Out-String
        Write-Host "Result:`n$result"
    }
} catch {
    Write-Host "$redX Failed to query MongoDB: $_"
    Write-Host "Run this MongoDB query manually:`n"
    Write-Host "  mongosh`n"
    Write-Host "  use auth_db  (or your database name)`n"
    Write-Host "  $query`n"
    exit 1
}

# Step 3: Promote to admin if requested
if ($FixRole) {
    Write-Host "`n$yellow Promoting user to admin role...$reset`n"
    
    $updateQuery = @"
db.users.findOneAndUpdate(
  {username: '$Username'},
  {`$set: {role: 'admin', updatedAt: new Date()}},
  {returnDocument: 'after'}
)
"@
    
    try {
        if ($mongoAvailable) {
            Write-Host "Executing update..."
            $result = mongosh --quiet --eval $updateQuery 2>&1 | Out-String
            Write-Host "Updated:`n$result"
        } else {
            Write-Host "Executing via Docker..."
            $result = docker exec $container mongosh --quiet --eval $updateQuery 2>&1 | Out-String
            Write-Host "Updated:`n$result"
        }
        Write-Host "`n$greenCheck User promoted to admin role"
        Write-Host "$yellow Next step: Re-login in browser to get fresh token with admin role`n"
    } catch {
        Write-Host "$redX Failed to update user role: $_"
        Write-Host "`nRun this manually in mongosh:`n"
        Write-Host "  $updateQuery`n"
    }
}

# Step 4: Show all admin users
Write-Host "`n📋 All admin users in system:`n"

$adminQuery = @"
db.users.find({role: 'admin'}, {username: 1, email: 1, role: 1}).toArray()
"@

try {
    if ($mongoAvailable) {
        $admins = mongosh --quiet --eval $adminQuery 2>&1 | Out-String
        Write-Host "$admins"
    } else {
        $admins = docker exec $container mongosh --quiet --eval $adminQuery 2>&1 | Out-String
        Write-Host "$admins"
    }
} catch {
    Write-Host "$yellow Could not list admins. Run manually: $adminQuery`n"
}

Write-Host "`n$blue=== Diagnostic Complete ===$reset`n"
