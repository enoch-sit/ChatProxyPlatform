# AWS CLI Checklist

These commands are for understanding and validating the deployment path. They are organized from read-only checks to rollback support.

## Identity and region

```powershell
aws --version
aws sts get-caller-identity --output json
aws configure get region
```

## Baseline ECS status

```powershell
powershell -ExecutionPolicy Bypass -File .\infra\scripts\audit-ecs-status.ps1 -Environment prod -AsJson
powershell -ExecutionPolicy Bypass -File .\infra\scripts\audit-ecs-status.ps1 -Environment dev -AsJson
```

## Direct ECS service checks

```powershell
aws ecs describe-services `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-flowise-proxy-service chatproxy-prod-bridge chatproxy-prod-auth-service chatproxy-prod-accounting-service `
  --region us-east-1 `
  --output json
```

## Secrets Manager pre-check for flowise-proxy

Safe presence check:

```powershell
aws secretsmanager describe-secret `
  --secret-id /chatproxy/prod/flowise/api-key `
  --region us-east-1 `
  --output json
```

If you need to confirm the shape without pasting the secret into logs, prefer a filtered query path or manual console verification.

## CloudWatch log groups

```powershell
aws logs describe-log-groups `
  --log-group-name-prefix /ecs/chatproxy-prod `
  --region us-east-1 `
  --query "logGroups[].logGroupName" `
  --output text
```

Observed log groups:

- `/ecs/chatproxy-prod-accounting`
- `/ecs/chatproxy-prod-auth`
- `/ecs/chatproxy-prod-bridge`
- `/ecs/chatproxy-prod-flowise`
- `/ecs/chatproxy-prod-flowise-proxy`

## Recent log events for the two likely patch targets

```powershell
aws logs tail /ecs/chatproxy-prod-flowise-proxy --since 30m --region us-east-1
aws logs tail /ecs/chatproxy-prod-bridge --since 30m --region us-east-1
```

## Task definition capture before deployment

```powershell
aws ecs describe-services `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-flowise-proxy-service `
  --region us-east-1 `
  --query "services[0].taskDefinition" `
  --output text

aws ecs describe-services `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-bridge `
  --region us-east-1 `
  --query "services[0].taskDefinition" `
  --output text
```

## Wait for stability after deployment

```powershell
aws ecs wait services-stable `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-flowise-proxy-service `
  --region us-east-1

aws ecs wait services-stable `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-bridge `
  --region us-east-1
```

## Manual rollback support if needed

Inspect current task definition:

```powershell
aws ecs describe-services `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-flowise-proxy-service `
  --region us-east-1 `
  --query "services[0].taskDefinition" `
  --output text
```

Force service back to a known task definition:

```powershell
aws ecs update-service `
  --cluster chatproxy-prod-cluster `
  --service chatproxy-prod-flowise-proxy-service `
  --task-definition <previous-task-definition-arn> `
  --force-new-deployment `
  --region us-east-1
```

Then wait again:

```powershell
aws ecs wait services-stable `
  --cluster chatproxy-prod-cluster `
  --services chatproxy-prod-flowise-proxy-service `
  --region us-east-1
```

## Important operator note

For production in this repo, the preferred mutation path is the `Deploy Prod` workflow, with AWS CLI used for baseline capture, live verification, and rollback support.