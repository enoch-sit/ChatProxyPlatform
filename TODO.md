# Feature Promotion TODO

Use this checklist when building a feature on `test/localdeploy` from this Windows workstation with a Docker-first local workflow and promoting it to the two production-class targets: `bhss` for Windows + Docker Desktop and `release/aws-prod-candidate` for AWS.

## Example Feature

Add chatflow name to admin chat history so admins can view it and update the related feature safely across both deployment lines.

## Workflow Pipeline

### 1. Create the feature branch

- Start from `test/localdeploy`
- Create a short-lived branch such as `feat/chat-history-chatflow-name`
- Do not start feature work on `bhss` or `release/aws-prod-candidate`

### 2. Implement the full feature bundle

- Do the feature development work on this Windows machine using the `test/localdeploy` branch or a short-lived branch created from it
- Use the Docker-managed local stack as the default dev loop on this machine, typically through `python local-deploy.py`
- Update backend data/query/API support for chatflow name
- Update admin UI to display the chatflow name
- Add any required update flow for admins
- Add or update tests for the touched slice
- Keep the whole feature on one branch until it works end-to-end

### 3. Validate on the feature branch

- Rebuild or redeploy the touched local containers first
- Run targeted tests for the touched services
- Run build or typecheck for affected services
- Smoke test the admin chat history behavior against the local Docker stack
- Confirm the feature works before promotion

### 4. Merge into `test/localdeploy`

- Open a PR into `test/localdeploy`
- Merge only after the feature bundle is validated
- Treat `test/localdeploy` as the single development source of truth

### 5. Promote the same commit set to `bhss`

- Promote the already-tested commit set from `test/localdeploy` to `bhss`
- Do not re-implement or manually diverge the feature on `bhss`
- Use `bhss` as the live Windows + Docker Desktop production line

### 6. Validate on `bhss`

- Verify admin chat history loads correctly
- Verify chatflow name is visible
- Verify admin update behavior works as expected
- Check for Windows or Docker Desktop specific runtime differences
- If `bhss` fails, fix the issue back on `test/localdeploy`, then re-promote

### 7. Promote the same commit set to AWS

- Promote the same tested commit set to `release/aws-prod-candidate`
- Do not create a separate AWS-only implementation unless the difference is purely environment-specific configuration

### 8. Validate on AWS

- Deploy from `release/aws-prod-candidate`
- Run the AWS smoke checks for the touched feature
- Confirm the admin workflow behaves the same as the validated `bhss` version
- If AWS exposes an issue, fix it on `test/localdeploy` first, then re-promote through `bhss` and AWS

## Rules

- Author the feature once on `test/localdeploy`
- Use this Windows workstation as the primary development environment for `test/localdeploy` work
- Default to Docker-first local development on this machine instead of host-only execution
- Promote the same commit set to both production targets
- Do not use `bhss` and AWS as separate development branches
- Do not patch feature-by-feature independently across long-lived branches
- Keep feature behavior aligned across Windows and AWS unless configuration differences require otherwise

## Quick Branch Flow

1. `test/localdeploy` -> create `feat/chat-history-chatflow-name`
2. `feat/chat-history-chatflow-name` -> merge into `test/localdeploy`
3. `test/localdeploy` -> promote same commit set to `bhss`
4. `test/localdeploy` -> promote same commit set to `release/aws-prod-candidate`

## How To Promote Code Without Overwriting Environment Config

The safe rule is: promote feature code, not environment-specific configuration.

### `bhss` promotion rule

- Keep `bhss` runtime and machine-specific config intact
- Promote application code from `test/localdeploy`
- Do not blindly overwrite Windows or Docker Desktop specific settings

Typical code paths that are usually safe to promote:

- `auth-service/src/**`
- `accounting-service/src/**`
- `bridge/src/**`
- `flowise-proxy-service-py/app/**`
- tests related to the feature

Typical files to avoid overwriting unless the feature truly requires them:

- `.env` files
- `docker-compose*.yml` files with BHSS-specific runtime differences
- local scripts and workstation-only settings
- secrets, ports, URLs, API keys, hostnames

Safer promotion pattern for BHSS:

```powershell
git restore --source test/localdeploy --worktree -- auth-service/src accounting-service/src bridge/src flowise-proxy-service-py/app
```

If the feature is already isolated into clean commits that do not touch config, cherry-pick can also be used:

```powershell
git cherry-pick <feature-commit-sha>
```

### AWS promotion rule

- Keep AWS-specific infrastructure and deployment config intact
- Promote the same tested application code from `test/localdeploy`
- Do not overwrite AWS runtime settings unless the feature explicitly requires an AWS config change

Typical AWS config surfaces to avoid overwriting blindly:

- `infra/environments/prod/terraform.tfvars`
- AWS secret values
- ECS, ALB, Route53, or environment-specific deployment metadata
- production `.env` or secret material

If the feature needs an AWS config change, handle it as a small AWS-specific follow-up change instead of mixing feature code and environment config in one promotion step.

### Working rule

- Split changes into two categories: feature code and environment config
- Promote feature code by default
- Leave environment config alone unless the feature cannot work without a controlled environment-specific change
- If an environment-specific issue appears on `bhss` or AWS, fix the code on `test/localdeploy` first, then re-promote

## Reference Docs

- `docs/BRANCHING_POLICY.md`
- `docs/PATCH_QUICK_REFERENCE.md`
- `docs/BRANCH_PROTECTION_CHECKLIST.md`
