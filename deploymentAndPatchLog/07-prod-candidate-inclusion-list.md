# Prod Candidate Inclusion List

## Purpose

This file turns the earlier scope assessment into a practical recommendation for a narrowed production candidate ref.

## Key conclusion

If the intended production release is primarily the current `bridge` and `flowise-proxy-service-py` work, the narrowed candidate should not simply be the whole current `release/aws` branch.

## Important versioning note

`version.json` was not part of the original `main...release/aws` diff, but it has now been intentionally added to the narrowed candidate branch.

Operational meaning:

- a `Deploy Prod` dispatch from the current branch would still generate new image tags because the git SHA is different
- the semantic service version would remain `1.0.0`
- the resulting tags would look like `v1.0.0-f9cc0d3` instead of the currently deployed `v1.0.0-b7d1ef7`

That gap has now been resolved in the narrowed candidate by bumping `bridge` and `flowise-proxy` to `1.0.1`.

## Recommended inclusion classes

### Must include for an app-only prod patch

These are the files most likely to belong in the narrowed prod candidate if the release is meant to ship the new admin UI and proxy behavior.

- `bridge/**`
- `flowise-proxy-service-py/**`

### Must include if GitHub Actions is your prod deployment path

These are not app features, but they are foundational if the current branch is also introducing the production workflow and prod Terraform environment needed by that workflow.

- `.github/workflows/deploy-prod.yml`
- `infra/environments/prod/main.tf`
- `infra/environments/prod/terraform.ci.tfvars`
- `infra/environments/prod/variables.tf`
- `infra/modules/platform/main.tf`
- `infra/modules/platform/variables.tf`
- `infra/modules/flowise-aws/main.tf`
- `infra/modules/flowise-aws/variables.tf`

Why these stay together:

- `deploy-prod.yml` is new on this branch and depends on `infra/environments/prod`
- `infra/environments/prod/*` is also new on this branch
- the module changes add `create_dns_records` gates used by the prod environment definitions

Without this set, the current branch’s GitHub Actions prod path is incomplete.

### Strongly recommended alongside the prod workflow

- `.github/workflows/rollback.yml`

Reason:

- this branch is what adds prod rollback support to the workflow
- if you introduce a new prod deploy path, keeping the matching prod rollback path is the safer operational choice

### Optional depending on your operator plan

- `infra/scripts/deploy-service.ps1`

Include this only if you expect to use the local operator path from Windows for production or want to keep the local and CI deploy mechanics aligned.

If the actual prod rollout will be GitHub Actions only, this file can be deferred without blocking the workflow path.

## Recommended exclusions for the narrowed prod candidate

Unless you intentionally want a broader release, defer these from the prod candidate:

- `auth-service/**`
- `accounting-service/**`
- `scripts/**`
- `local-deploy.py`
- `patch.ps1`
- workstation and WireGuard files
- batch and probe scripts
- `fleet-inventory.json`
- `.env.*.template`
- docs unrelated to the actual production release gate

## Suggested narrowed candidate set

### Minimal viable prod candidate using current GitHub Actions path

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
- `version.json`

### Optional addition

- `infra/scripts/deploy-service.ps1`

## Deployment recommendation from this point

1. Create a narrowed ref from the list above.
2. Decide whether to bump `version.json` for `flowise-proxy` and `bridge`.
3. Re-run the prod readiness review against that narrowed ref only.
4. If the dev Flowise `401` issue is not fixed in that ref, explicitly document why it is safe to proceed anyway.

## Bottom line

The best current production candidate is not the full `release/aws` branch. It is a narrowed set centered on `bridge`, `flowise-proxy-service-py`, and the prod workflow/Terraform files that make the current GitHub Actions prod path possible.