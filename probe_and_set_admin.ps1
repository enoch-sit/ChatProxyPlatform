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

function Test-HttpGet {
    param([string]$Url)

    $result = [ordered]@{
        Url = $Url
        Ok = $false
        StatusCode = 0
        Body = ""
        Error = ""
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -Method GET -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
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
    }

    return [pscustomobject]$result
}

function Invoke-AuthContainerProbe {
    param(
        [string]$Path,
        [hashtable]$Body
    )

    $nodeScript = @'
const url = process.env.TARGET_URL;
const body = process.env.TARGET_BODY ? JSON.parse(process.env.TARGET_BODY) : undefined;

(async () => {
  const response = await fetch(url, {
    method: body ? 'POST' : 'GET',
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await response.text();
  process.stdout.write(JSON.stringify({
    ok: response.ok,
    statusCode: response.status,
    body: text
  }));
})().catch((err) => {
  process.stdout.write(JSON.stringify({
    ok: false,
    statusCode: 0,
    body: '',
    error: err && err.message ? err.message : String(err)
  }));
  process.exit(1);
});
'@

    $targetUrl = "http://127.0.0.1:3000$Path"
    $targetBody = if ($Body) { ($Body | ConvertTo-Json -Depth 5 -Compress) } else { "" }
    $output = & docker exec `
        -e "TARGET_URL=$targetUrl" `
        -e "TARGET_BODY=$targetBody" `
        auth-service node -e $nodeScript 2>&1

    $jsonText = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        return [pscustomobject]@{
            Ok = $false
            StatusCode = 0
            Body = ""
            Error = "No output from auth-service container probe"
        }
    }

    try {
        $parsed = $jsonText | ConvertFrom-Json
        return [pscustomobject]@{
            Ok = [bool]$parsed.ok
            StatusCode = [int]$parsed.statusCode
            Body = [string]$parsed.body
            Error = [string]$parsed.error
        }
    }
    catch {
        return [pscustomobject]@{
            Ok = $false
            StatusCode = 0
            Body = $jsonText
            Error = "Could not parse container probe output"
        }
    }
}

function Write-RecentAuthLogs {
    param([int]$Tail = 20)

    Write-Info "auth-service recent logs (last $Tail lines):"
    $logs = & docker logs auth-service --tail=$Tail 2>&1
    if ($LASTEXITCODE -eq 0) {
        $logs | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Warn "Could not read auth-service logs"
        ($logs | Out-String).Trim() -split "`r?`n" | ForEach-Object { if ($_){ Write-Host "  $_" } }
    }
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

# Apply seed defaults before prompting or validating
if ([string]::IsNullOrWhiteSpace($Username)) { $Username = "admin" }
if ([string]::IsNullOrWhiteSpace($Email))    { $Email    = "admin@admin.com" }
if ([string]::IsNullOrWhiteSpace($Password)) { $Password = "admin@admin" }

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
$hostHealth = Test-HttpGet -Url "http://localhost:3000/health"
if ($hostHealth.Ok -and $hostHealth.StatusCode -eq 200) {
    Write-Ok "auth-service health endpoint responds on localhost"
} else {
    Write-Warn "auth-service health endpoint is not healthy from localhost (HTTP $($hostHealth.StatusCode))"
    if ($hostHealth.Error) { Write-Host "  Error: $($hostHealth.Error)" }
}

$finalLogin = Test-AdminLogin -ProbeUsername $Username -ProbePassword $Password
if ($finalLogin.Ok -and $finalLogin.StatusCode -eq 200) {
    Write-Ok "auth-service login now works for $Username / $Password"
} else {
    Write-Warn "Host-side auth login probe still failed (HTTP $($finalLogin.StatusCode))"
    if ($finalLogin.Body) { Write-Host "  Body : $($finalLogin.Body)" }
    if ($finalLogin.Error) { Write-Host "  Error: $($finalLogin.Error)" }

    Write-Info "Re-checking auth from inside the auth-service container..."
    $containerHealth = Invoke-AuthContainerProbe -Path "/health"
    if ($containerHealth.Ok -and $containerHealth.StatusCode -eq 200) {
        Write-Ok "auth-service container health probe succeeded"
    } else {
        Write-Warn "auth-service container health probe failed (HTTP $($containerHealth.StatusCode))"
        if ($containerHealth.Error) { Write-Host "  Error: $($containerHealth.Error)" }
    }

    $containerLogin = Invoke-AuthContainerProbe -Path "/api/auth/login" -Body @{ username = $Username; password = $Password }
    if ($containerLogin.Ok -and $containerLogin.StatusCode -eq 200) {
        Write-Ok "auth-service container login probe succeeded"
        Write-Warn "The credentials are set correctly, but the host-side localhost probe is still failing. Check host networking or rerun diagnose_auth_connection.ps1 if Bridge login still fails."
    } else {
        Write-Fail "Auth login still failed from inside the auth-service container (HTTP $($containerLogin.StatusCode))"
        if ($containerLogin.Body) { Write-Host "  Body : $($containerLogin.Body)" }
        if ($containerLogin.Error) { Write-Host "  Error: $($containerLogin.Error)" }
        Write-RecentAuthLogs -Tail 30
        exit 1
    }
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