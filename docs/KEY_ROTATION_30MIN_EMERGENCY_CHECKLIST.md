# 30-Minute Emergency Checklist: Key Rotation + Admin Recovery

Use this during an active security incident or suspected credential exposure.

## 0) Immediate Containment (2 minutes)

1. Announce maintenance window (users will be logged out).
2. Verify AWS identity:

```powershell
aws sts get-caller-identity
```

3. Set base values:

```powershell
$REGION  = "us-east-1"
$CLUSTER = "chatproxy-dev-cluster"
```

## 1) Rotate JWT Keys (3 minutes)

```powershell
$ACCESS  = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$REFRESH = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))

aws secretsmanager put-secret-value `
  --region $REGION `
  --secret-id /chatproxy/dev/jwt `
  --secret-string "{`"JWT_ACCESS_SECRET`":`"$ACCESS`",`"JWT_REFRESH_SECRET`":`"$REFRESH`"}"
```

## 2) Rotate DB + SMTP Secrets (8 minutes)

```powershell
powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-db-secrets.ps1
powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-mongodb-secrets.ps1
powershell -ExecutionPolicy Bypass -File infra/scripts/smtp.ps1
```

If Flowise API key may be exposed, rotate it too:

```powershell
powershell -ExecutionPolicy Bypass -File fix_flowise_apikey_secret.ps1
```

## 3) Force Service Redeploys (5 minutes)

```powershell
aws ecs update-service --cluster $CLUSTER --service chatproxy-dev-auth-service --force-new-deployment --region $REGION
aws ecs update-service --cluster $CLUSTER --service chatproxy-dev-accounting-service --force-new-deployment --region $REGION
aws ecs update-service --cluster $CLUSTER --service chatproxy-dev-flowise-proxy-service --force-new-deployment --region $REGION
```

Wait until services stabilize:

```powershell
aws ecs describe-services --cluster $CLUSTER --services chatproxy-dev-auth-service chatproxy-dev-accounting-service chatproxy-dev-flowise-proxy-service --region $REGION --query "services[*].{name:serviceName,running:runningCount,desired:desiredCount,status:status}" --output table
```

## 4) Reset Admin Password (Normal Path) (5 minutes)

```powershell
$BASE = "https://YOUR_DOMAIN"
$CURRENT = "CURRENT_ADMIN_PASSWORD"
$NEW = [System.Web.Security.Membership]::GeneratePassword(24,6)
$NEW

$loginBody = @{ username = "admin"; password = $CURRENT } | ConvertTo-Json
$login = Invoke-RestMethod -Method POST -Uri "$BASE/api/auth/login" -ContentType "application/json" -Body $loginBody
$token = $login.accessToken

$changeBody = @{ currentPassword = $CURRENT; newPassword = $NEW } | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri "$BASE/api/change-password" -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" -Body $changeBody
```

Important: the URL must be quoted in PowerShell variable assignment.

Store `$NEW` in your password manager immediately.

## 5) If Admin Password Is Lost (Break-Glass) (5 minutes)

Current code includes testing recovery routes:
- `POST /api/testing/verify-user/:userId`
- `POST /api/testing/promote-admin/:userId`

Recovery sequence:
1. Create temporary user with signup.
2. Verify temp user via testing route.
3. Promote temp user via testing route.
4. Login as temp admin and reset original admin credentials.
5. Remove temporary admin user.
6. Remove/disable testing routes and redeploy auth-service.

## 6) Verification (2 minutes)

```powershell
curl https://YOUR_DOMAIN/api/auth/health
curl https://YOUR_DOMAIN/api/accounting/health
curl https://YOUR_DOMAIN/api/v1/chat/health
```

Functional checks:
1. Old tokens fail with 401.
2. New admin login succeeds.
3. Admin dashboard loads (users, credits, usage).
4. Password reset email flow works.

## 7) Post-Incident Actions (Do not skip)

1. Remove exposed values from docs/log files.
2. Rotate any IAM user access keys used during incident response.
3. Commit and deploy cleanup (especially testing routes if used).
4. Schedule follow-up rotation in 7 days.

## Copy/Paste Ultra-Quick Block

```powershell
$REGION  = "us-east-1"
$CLUSTER = "chatproxy-dev-cluster"

$ACCESS  = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$REFRESH = [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
aws secretsmanager put-secret-value --region $REGION --secret-id /chatproxy/dev/jwt --secret-string "{`"JWT_ACCESS_SECRET`":`"$ACCESS`",`"JWT_REFRESH_SECRET`":`"$REFRESH`"}"

powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-db-secrets.ps1
powershell -ExecutionPolicy Bypass -File infra/scripts/rotate-mongodb-secrets.ps1
powershell -ExecutionPolicy Bypass -File infra/scripts/smtp.ps1

aws ecs update-service --cluster $CLUSTER --service chatproxy-dev-auth-service --force-new-deployment --region $REGION
aws ecs update-service --cluster $CLUSTER --service chatproxy-dev-accounting-service --force-new-deployment --region $REGION
aws ecs update-service --cluster $CLUSTER --service chatproxy-dev-flowise-proxy-service --force-new-deployment --region $REGION
```