# Branch Protection Checklist

This repository's branch roles are defined in [BRANCHING_POLICY.md](BRANCHING_POLICY.md).

Branch protection is configured in GitHub repository settings, not in tracked source files. Use this checklist to align GitHub settings with the current workflow.

## Protected Long-Lived Branches

Apply protection to these branches:

- `test/localdeploy`
- `bhss`
- `release/aws-prod-candidate`

## Recommended Rules

### `test/localdeploy`

- Require a pull request before merging
- Require at least 1 approval
- Dismiss stale approvals when new commits are pushed
- Require conversation resolution before merging
- Require status checks to pass before merging
- Required checks:
  - `changes`
  - `auth-service`
  - `accounting-service`
  - `flowise-proxy`
  - `bridge`
  - `terraform`
- Restrict direct pushes except for trusted maintainers if needed
- Allow squash merge or rebase merge, but use one merge style consistently

### `bhss`

- Require a pull request before merging
- Require at least 1 approval
- Require conversation resolution before merging
- Require status checks to pass before merging
- Treat this branch as a live Windows + Docker Desktop production target
- Required checks:
  - `changes`
  - `auth-service`
  - `accounting-service`
  - `flowise-proxy`
  - `bridge`
  - `terraform`
- Restrict direct pushes to release maintainers only

### `release/aws-prod-candidate`

- Require a pull request before merging
- Require at least 1 approval
- Require conversation resolution before merging
- Require status checks to pass before merging
- Required checks:
  - `changes`
  - `auth-service`
  - `accounting-service`
  - `flowise-proxy`
  - `bridge`
  - `terraform`
- Restrict direct pushes to release maintainers only
- Consider requiring linear history if you want cleaner promotion traceability

## Operational Notes

- Feature branches should not be protected by default.
- New work starts from `test/localdeploy` using short-lived branch prefixes such as `feat/...`, `fix/...`, `hotfix/...`, `refactor/...`, `chore/...`, `ops/...`, and `spike/...`.
- `bhss` and `release/aws-prod-candidate` are production-class promotion branches, not primary feature-authoring branches.
- `bhss` represents the live Windows + Docker Desktop deployment line; `release/aws-prod-candidate` represents the AWS deployment line.
- If CI job names change in workflow files, update the required status checks in GitHub settings to match the new job names.

## Suggested Promotion Path

1. Merge feature branch into `test/localdeploy`
2. Promote the same commit set to `bhss` and validate or deploy on the Windows target
3. Promote the same commit set to `release/aws-prod-candidate` and validate or deploy on AWS
4. Keep the deployed commit sets traceable across both production branches
