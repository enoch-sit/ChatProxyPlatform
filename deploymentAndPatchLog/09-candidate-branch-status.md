# Candidate Branch Status

## Current branch

- Active branch: `release/aws-prod-candidate`
- Base branch used: `main`
- Source restored from: `release/aws`
- Current committed candidate SHA: `d8edea2`

## What was done

A narrowed production candidate worktree was created by:

1. switching to `main`
2. creating `release/aws-prod-candidate`
3. restoring only the approved prod candidate paths from `release/aws`

This candidate now exists as a real branch and a real commit.

## Scope validation result

Validated during this session:

- no `auth-service` files are present in the narrowed candidate worktree
- no `accounting-service` files are present in the narrowed candidate worktree
- expected new prod-only files are present as untracked additions:
  - `.github/workflows/deploy-prod.yml`
  - `infra/environments/prod/`

## Current candidate contents

### Modified tracked files

- `.github/workflows/rollback.yml`
- `bridge/**`
- `flowise-proxy-service-py/**`
- `infra/modules/flowise-aws/*`
- `infra/modules/platform/*`

### Untracked candidate files

- `.github/workflows/deploy-prod.yml`
- `infra/environments/prod/`

### Other untracked files preserved in the repo

These are not part of the committed narrowed prod candidate, but remain present in the local working tree:

- `deploymentAndPatchLog/`
- `infra/scripts/audit-ecs-status.ps1`
- `scripts/update_aws_secret.py`

## Interpretation

The narrowing step worked as intended.

The candidate worktree now contains the expected app, workflow, and prod Terraform surface without backend spillover from `auth-service` or `accounting-service`.

## What is still not done

1. The dev Flowise `401 Unauthorized` issue is still an open release note item.
2. The deployment log folder and two unrelated untracked helper scripts are still local-only artifacts, not part of commit `d8edea2`.

## Versioning status

`version.json` is now part of the narrowed candidate.

Current candidate version metadata:

- top-level version: `1.0.1`
- `flowise-proxy`: `1.0.1`
- `bridge`: `1.0.1`
- `auth-service`: `1.0.0`
- `accounting-service`: `1.0.0`

Operational meaning:

- a `Deploy Prod` run from this narrowed candidate would generate tags based on `v1.0.1-<gitsha7>` for `flowise-proxy` and `bridge`
- the candidate now carries an explicit patch identity instead of reusing `1.0.0`

## Next review checkpoint

Before any production deploy, review these raw artifacts:

- `narrowed-candidate-status.txt`
- `narrowed-candidate-tracked-diff.txt`

Also review the exact committed diff from `main...d8edea2`.

Then decide:

1. whether to keep the candidate exactly as-is
2. whether to add `infra/scripts/deploy-service.ps1`
3. whether the dev Flowise auth issue is sufficiently explained for promotion

## Final branch-scoped validation

Validated after commit `d8edea2`:

- `main...HEAD` includes only the narrowed candidate app, workflow, Terraform, module, and `version.json` files
- no `auth-service/**` files are present in the committed diff
- no `accounting-service/**` files are present in the committed diff