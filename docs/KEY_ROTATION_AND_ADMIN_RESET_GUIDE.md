# Key Rotation and Admin Account Reset Guide

This guide is for your current AWS deployment.

For incident response, use the fast version: `docs/KEY_ROTATION_30MIN_EMERGENCY_CHECKLIST.md`

## Scope

This runbook rotates:
- JWT signing keys
- Database credentials (MongoDB and PostgreSQL secrets)
- SES SMTP credentials
- Flowise API key secret
- Optional AWS IAM access keys used by humans

And it covers:
- Resetting admin password (normal path)
- Recovering admin access if password is lost (break-glass path)

## Before You Start

1. Schedule a maintenance window (users will be logged out during JWT rotation).
2. Confirm AWS CLI is authenticated:

```powershell
aws sts get-caller-identity
```

3. Use region `us-east-1` unless your deployment differs.
4. Keep this order: **rotate secrets -> redeploy services -> verify -> retire old credentials**.

## Secret Inventory (Current Naming)

- `/chatproxy/dev/jwt`
- `/chatproxy/dev/db/accounting`
- `/chatproxy/dev/db/flowise`
- `/chatproxy/dev/mongodb/auth`
- `/chatproxy/dev/mongodb/proxy`
- `/chatproxy/dev/flowise/api-key`
- `/chatproxy/dev/ses`

## Recommended Rotation Order

1. JWT keys
2. Database secrets
3. SES SMTP credentials
4. Flowise API key
5. IAM user access keys (if applicable)
6. Admin password reset

## 1) Rotate JWT Keys

This invalidates existing access/refresh tokens by design.

```powershell
$ACCESS  = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$REFRESH = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))

aws secretsmanager put-secret-value `
  --region us-east-1 `
  --secret-id /chatproxy/dev/jwt `
  --secret-string "{`"JWT_ACCESS_SECRET`":`"$ACCESS`",`"JWT_REFRESH_SECRET`":`"$REFRESH`"}"
```

Then redeploy services that verify or issue tokens:
- auth-service
- accounting-service
- flowise-proxy

Example:

```powershell
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-auth-service --force-new-deployment --region us-east-1
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-accounting-service --force-new-deployment --region us-east-1
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-flowise-proxy-service --force-new-deployment --region us-east-1
```

## 2) Rotate Database Secrets

Use existing scripts in `infra/scripts`.

### 2.1 Rotate PostgreSQL-related secrets

```powershell
powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-db-secrets.ps1
```

### 2.2 Rotate MongoDB-related secrets

```powershell
powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-mongodb-secrets.ps1
```

After rotation, redeploy dependent services:
- auth-service (Mongo auth secret)
- flowise-proxy (Mongo proxy secret)
- accounting-service (DB accounting secret)

## 3) Rotate SES SMTP Credentials

```powershell
powershell -ExecutionPolicy Bypass -File infra/scripts/smtp.ps1
```

Then redeploy auth-service (it sends email and reads SES secret):

```powershell
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-auth-service --force-new-deployment --region us-east-1
```

## 4) Rotate Flowise API Key Secret

If you generated a new key in Flowise UI:

```powershell
powershell -ExecutionPolicy Bypass -File fix_flowise_apikey_secret.ps1
```

Then redeploy flowise-proxy:

```powershell
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-flowise-proxy-service --force-new-deployment --region us-east-1
```

## 5) Rotate AWS IAM Access Keys (Human Users)

If you use long-lived IAM user keys locally:

1. Create a new key in IAM.
2. Update local CLI profile:

```powershell
aws configure
```

3. Verify:

```powershell
aws sts get-caller-identity
```

4. Delete old key immediately in IAM.

## 6) Reset Admin Password (Normal Path)

Use when you still know the current admin password.

1. Login to obtain access token:

```powershell
$BASE = "https://YOUR_DOMAIN"
$loginBody = @{ username = "admin"; password = "CURRENT_PASSWORD" } | ConvertTo-Json
$login = Invoke-RestMethod -Method POST -Uri "$BASE/api/auth/login" -ContentType "application/json" -Body $loginBody
$token = $login.accessToken
```

Important: keep the URL in quotes. In PowerShell, this is invalid and will fail: `$BASE = https://YOUR_DOMAIN`
Also avoid a trailing slash in `$BASE`. If `$BASE` ends with `/`, then `"$BASE/api/auth/login"` becomes `//api/auth/login`, which may be routed incorrectly and return `405`.

If you get `{"error":"Invalid credentials"}`:
1. Try both username and email forms:

```powershell
$loginBody = @{ username = "admin"; password = "CURRENT_PASSWORD" } | ConvertTo-Json
# or
$loginBody = @{ username = "admin@example.com"; password = "CURRENT_PASSWORD" } | ConvertTo-Json
```

Note: in your current deployment, `username = "admin"` is the reliable login form.

2. If neither works, switch to Section 7 (Break-Glass recovery) to regain admin access, then return to Section 6.

2. Change password via endpoint:

```powershell
$changeBody = @{ currentPassword = "CURRENT_PASSWORD"; newPassword = "NEW_STRONG_PASSWORD" } | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri "$BASE/api/change-password" -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" -Body $changeBody
```

3. Confirm old password fails and new password succeeds.

## 7) Recover Admin Access (Break-Glass)

Use only if admin password is lost.

### Option A (if testing recovery route is enabled)

Your current code includes:
- `POST /api/testing/verify-user/:userId`
- `POST /api/testing/promote-admin/:userId`

Recovery flow:
1. Create a temporary user via signup.
2. Verify user with `/api/testing/verify-user/:userId`.
3. Promote with `/api/testing/promote-admin/:userId`.
4. Login as temporary admin.
5. Reset original admin account password or role.
6. Remove temporary admin user.
7. Remove/disable testing routes and redeploy.

### Option B (DB-level emergency recovery)

If testing routes are unavailable, use controlled DB access to set admin role and force password reset process. Record all actions and remove temporary access immediately after recovery.

## 8) Post-Rotation Verification Checklist

1. Auth login works with new credentials.
2. Admin dashboard loads.
3. Credits and usage endpoints succeed.
4. Email send (password reset/verification) works.
5. Old JWT tokens fail with 401.
6. ECS services are healthy and steady-state.

Useful health checks:

```powershell
curl https://YOUR_DOMAIN/api/auth/health
curl https://YOUR_DOMAIN/api/accounting/health
curl https://YOUR_DOMAIN/api/v1/chat/health
```

## 9) Hardening After Recovery

1. Remove plaintext secrets from docs/log artifacts.
2. Remove any temporary testing endpoints from production builds.
3. Ensure `.env` files with real values are not committed.
4. Set a recurring rotation schedule (for example every 60-90 days).
5. Use password manager storage for admin credentials.

## Quick Command Block (If You Need Fast Execution)

```powershell
# 1) JWT
$ACCESS  = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$REFRESH = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
aws secretsmanager put-secret-value --region us-east-1 --secret-id /chatproxy/dev/jwt --secret-string "{`"JWT_ACCESS_SECRET`":`"$ACCESS`",`"JWT_REFRESH_SECRET`":`"$REFRESH`"}"

# 2) DB secrets
powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-db-secrets.ps1
powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-mongodb-secrets.ps1

# 3) SES
powershell -ExecutionPolicy Bypass -File infra/scripts/smtp.ps1

# 4) Redeploy services
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-auth-service --force-new-deployment --region us-east-1
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-accounting-service --force-new-deployment --region us-east-1
aws ecs update-service --cluster chatproxy-dev-cluster --service chatproxy-dev-flowise-proxy-service --force-new-deployment --region us-east-1
```
