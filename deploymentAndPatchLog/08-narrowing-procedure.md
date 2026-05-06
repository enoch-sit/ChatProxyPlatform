# Narrowing Procedure

## Why this exists

The current `release/aws` branch is broader than the likely intended production patch. This procedure gives you a mechanical way to build a narrowed production candidate ref.

## Recommended target contents

Include:

- `bridge/**`
- `flowise-proxy-service-py/**`
- `.github/workflows/deploy-prod.yml`
- `.github/workflows/rollback.yml`
- `infra/environments/prod/main.tf`
- `infra/environments/prod/terraform.ci.tfvars`
- `infra/environments/prod/variables.tf`
- `infra/modules/platform/main.tf`
- `infra/modules/platform/variables.tf`
- `infra/modules/flowise-aws/main.tf`
- `infra/modules/flowise-aws/variables.tf`
- optionally `version.json`
- optionally `infra/scripts/deploy-service.ps1`

Exclude unless explicitly intended for this production release:

- `auth-service/**`
- `accounting-service/**`
- local deploy and patch scripts
- fleet and workstation files
- batch/probe scripts
- unrelated docs and templates

## Safe git workflow

Because this repo currently has untracked files and the source branch is mixed, the safest approach is:

1. Start from `main`.
2. Create a new temporary release branch.
3. Restore only the approved path list from `release/aws`.
4. Review the diff.
5. Bump `version.json` if desired.
6. Run the final readiness review against that narrowed branch.

## Suggested commands

Run these only when you are ready to create the narrowed candidate branch.

```powershell
git switch main
git pull
git switch -c release/aws-prod-candidate

git restore --source release/aws -- \
  bridge \
  flowise-proxy-service-py \
  .github/workflows/deploy-prod.yml \
  .github/workflows/rollback.yml \
  infra/environments/prod/main.tf \
  infra/environments/prod/terraform.ci.tfvars \
  infra/environments/prod/variables.tf \
  infra/modules/platform/main.tf \
  infra/modules/platform/variables.tf \
  infra/modules/flowise-aws/main.tf \
  infra/modules/flowise-aws/variables.tf
```

Optional additions:

```powershell
git restore --source release/aws -- version.json
git restore --source release/aws -- infra/scripts/deploy-service.ps1
```

## Review commands after restore

```powershell
git status --short
git diff --stat main...HEAD
git diff --name-only main...HEAD
```

## What to verify before promotion

1. The diff contains only the intended files.
2. `version.json` is either intentionally unchanged or intentionally bumped.
3. The branch still contains the prod workflow and prod Terraform environment files required by `Deploy Prod`.
4. No `auth-service` or `accounting-service` changes remain unless explicitly approved.

## Ready-for-review outcome

Once the narrowed branch exists, the next validation pass should answer only two questions:

1. Is the narrowed ref the exact prod patch set you intend to ship?
2. Is the unresolved dev Flowise `401` issue explained well enough to permit promotion?

## Note on local repo state

This procedure is documented here instead of executed automatically because creating a branch changes git state, and the current repo also has untracked files that should remain under your control.