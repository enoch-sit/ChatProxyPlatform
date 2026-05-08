#!/usr/bin/env pwsh
param(
    [string]$Username,
    [string]$Email,
    [string]$Password,
    [string[]]$MongoUris = @(
        "mongodb://mongodb-auth:27017/auth_db",
        "mongodb://mongodb:27017/auth_db"
    ),
    [switch]$ForceReset,
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Ok { param([string]$Message) Write-Host "[OK]   $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "[FAIL] $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }

function Read-ValueOrDefault {
    param(
        [string]$Prompt,
        [string]$DefaultValue,
        [switch]$Secret
    )

    $suffix = if ($DefaultValue) { " [$DefaultValue]" } else { "" }
    $entered = if ($Secret) {
        Read-Host "$Prompt$suffix"
    } else {
        Read-Host "$Prompt$suffix"
    }

    if ([string]::IsNullOrWhiteSpace($entered)) {
        return $DefaultValue
    }

    return $entered.Trim()
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-RunningContainer {
    param([string]$Name)

    try {
        return (docker ps --filter "name=^$Name$" --format "{{.Names}}" 2>$null | Select-Object -First 1)
    }
    catch {
        return $null
    }
}

function Invoke-JsonPost {
    param(
        [string]$Url,
        [hashtable]$Body
    )

    $result = [ordered]@{
        Url = $Url
        Ok = $false
        StatusCode = 0
        Body = ""
        Error = ""
    }

    try {
        $json = $Body | ConvertTo-Json -Depth 5
        $response = Invoke-WebRequest -Uri $Url -Method POST -ContentType "application/json" -Body $json -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $result.Ok = $true
        $result.StatusCode = [int]$response.StatusCode
        $result.Body = $response.Content
    }
    catch {
        $exception = $_.Exception
        if ($exception.Response -and $exception.Response.StatusCode) {
            $result.StatusCode = [int]$exception.Response.StatusCode
        }
        $result.Error = $exception.Message

        try {
            if ($exception.Response -and $exception.Response.GetResponseStream()) {
                $reader = New-Object System.IO.StreamReader($exception.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
                if ($body) {
                    $result.Body = $body
                }
            }
        }
        catch { }
    }

    return [pscustomobject]$result
}

function Test-AdminLogin {
    param(
        [string]$ProbeUsername,
        [string]$ProbePassword
    )

    return Invoke-JsonPost -Url "http://localhost:3000/api/auth/login" -Body @{ username = $ProbeUsername; password = $ProbePassword }
}

function Invoke-AdminReset {
    param(
        [string]$MongoUri,
        [string]$AdminUsername,
        [string]$AdminEmail,
        [string]$AdminPassword
    )

    $nodeScript = @'
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

(async () => {
  const username = process.env.ADMIN_USERNAME;
  const email = String(process.env.ADMIN_EMAIL || '').toLowerCase();
  const password = process.env.ADMIN_PASSWORD;
  const mongoUri = process.env.MONGO_URI;

  if (!mongoUri) {
    throw new Error('MONGO_URI is required');
  }

  await mongoose.connect(mongoUri);

  const users = mongoose.connection.collection('users');
  const now = new Date();
  const passwordHash = await bcrypt.hash(password, 10);
  const existing = await users.findOne({
    $or: [
      { role: 'admin' },
      { username },
      { email }
    ]
  });

  if (existing) {
    await users.updateOne(
      { _id: existing._id },
      {
        $set: {
          username,
          email,
          password: passwordHash,
          isVerified: true,
          role: 'admin',
          updatedAt: now
        }
      }
    );
    console.log(`UPDATED_ADMIN:${existing._id}`);
  } else {
    const inserted = await users.insertOne({
      username,
      email,
      password: passwordHash,
      isVerified: true,
      role: 'admin',
      createdAt: now,
      updatedAt: now
    });
    console.log(`CREATED_ADMIN:${inserted.insertedId}`);
  }

  await mongoose.disconnect();
})().catch((err) => {
  console.error(err && err.stack ? err.stack : String(err));
  process.exit(1);
});
'@

    $output = & docker exec `
        -e "MONGO_URI=$MongoUri" `
        -e "ADMIN_USERNAME=$AdminUsername" `
        -e "ADMIN_EMAIL=$AdminEmail" `
        -e "ADMIN_PASSWORD=$AdminPassword" `
        auth-service node -e $nodeScript 2>&1

    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String).Trim()
    }
}

Write-Section "Probe And Set Admin"

if (-not $NoPrompt) {
    Write-Info "Enter the admin credentials to probe/set on this machine"
    $Username = Read-ValueOrDefault -Prompt "Admin username" -DefaultValue $Username
    $Email = Read-ValueOrDefault -Prompt "Admin email" -DefaultValue $Email
    $Password = Read-ValueOrDefault -Prompt "Admin password" -DefaultValue $Password -Secret
}

if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($Password)) {
    Write-Fail "Username, email, and password are required. Pass them as parameters or enter them at the prompts."
    exit 1
}

Write-Host "Time      : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Machine   : $env:COMPUTERNAME"
Write-Host "Username  : $Username"
Write-Host "Email     : $Email"
Write-Host "Password  : <redacted>"

if (-not (Test-CommandExists "docker")) {
    Write-Fail "docker is not available in PATH"
    exit 1
}

$authContainer = Get-RunningContainer -Name "auth-service"
$mongoContainer = Get-RunningContainer -Name "mongodb-auth"

Write-Section "Container Check"
if ($authContainer -eq "auth-service") {
    Write-Ok "auth-service is running"
} else {
    Write-Fail "auth-service is not running"
    Write-Info "Start it with: cd auth-service ; docker compose -f docker-compose.dev.yml up -d"
    exit 1
}

if ($mongoContainer -eq "mongodb-auth") {
    Write-Ok "mongodb-auth is running"
} else {
    Write-Warn "mongodb-auth is not running or not named as expected"
    Write-Info "The script will still try both default Mongo URIs"
}

Write-Section "Initial Probe"
$initialLogin = Test-AdminLogin -ProbeUsername $Username -ProbePassword $Password
if ($initialLogin.Ok -and $initialLogin.StatusCode -eq 200) {
    Write-Ok "auth-service login already works for $Username"
    if (-not $ForceReset) {
        Write-Info "Use -ForceReset if you want to rewrite the admin credentials anyway"
        exit 0
    }
    Write-Warn "ForceReset requested, continuing with admin reset"
} else {
    Write-Warn "Current login probe failed (HTTP $($initialLogin.StatusCode))"
    if ($initialLogin.Body) { Write-Host "  Body : $($initialLogin.Body)" }
    if ($initialLogin.Error) { Write-Host "  Error: $($initialLogin.Error)" }
}

Write-Section "Reset Or Create Admin"
$resetSucceeded = $false
foreach ($mongoUri in $MongoUris) {
    Write-Info "Trying Mongo URI: $mongoUri"
    $resetResult = Invoke-AdminReset -MongoUri $mongoUri -AdminUsername $Username -AdminEmail $Email -AdminPassword $Password
    if ($resetResult.ExitCode -eq 0) {
        Write-Ok "Admin create/reset succeeded via $mongoUri"
        if ($resetResult.Output) { Write-Host "  $($resetResult.Output)" }
        $resetSucceeded = $true
        break
    }

    Write-Warn "Admin create/reset failed via $mongoUri"
    if ($resetResult.Output) {
        $resetResult.Output -split "`r?`n" | ForEach-Object { Write-Host "  $_" }
    }
}

if (-not $resetSucceeded) {
    Write-Fail "Could not create/reset the admin user with any configured Mongo URI"
    exit 1
}

Write-Section "Post-Reset Probe"
$finalLogin = Test-AdminLogin -ProbeUsername $Username -ProbePassword $Password
if ($finalLogin.Ok -and $finalLogin.StatusCode -eq 200) {
    Write-Ok "auth-service login now works for $Username / $Password"
} else {
    Write-Fail "Admin reset completed, but login still failed (HTTP $($finalLogin.StatusCode))"
    if ($finalLogin.Body) { Write-Host "  Body : $($finalLogin.Body)" }
    if ($finalLogin.Error) { Write-Host "  Error: $($finalLogin.Error)" }
    exit 1
}

Write-Section "Proxy Probe"
$proxyContainer = Get-RunningContainer -Name "flowise-proxy"
if ($proxyContainer -eq "flowise-proxy") {
    $proxyLogin = Invoke-JsonPost -Url "http://localhost:8000/api/v1/chat/authenticate" -Body @{ username = $Username; password = $Password }
    if ($proxyLogin.Ok -and $proxyLogin.StatusCode -eq 200) {
        Write-Ok "flowise-proxy authenticate also works"
    } else {
        Write-Warn "flowise-proxy authenticate still fails (HTTP $($proxyLogin.StatusCode))"
        if ($proxyLogin.Body) { Write-Host "  Body : $($proxyLogin.Body)" }
        if ($proxyLogin.Error) { Write-Host "  Error: $($proxyLogin.Error)" }
    }
} else {
    Write-Warn "flowise-proxy is not running; skipped bridge-path probe"
}

Write-Section "Done"
Write-Ok "Admin credentials are set to $Username / $Password"
exit 0