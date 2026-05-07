# Branching Policy

This repository uses a promotion workflow with `test/localdeploy` as the development source of truth.

## Long-Lived Branch Roles

Use each long-lived branch for one job only:

- `test/localdeploy`
  - Primary integration branch
  - Source of truth for new feature development
  - Developed and validated first on the primary Windows workstation environment
  - Uses the Docker-managed local stack as the default development workflow on that machine
  - All feature branches start from here and merge back here first
- `bhss`
  - Windows production branch
  - Receives already-tested changes from `test/localdeploy`
  - Used for the live Windows + Docker Desktop deployment line
  - Not used for primary feature authoring
- `release/aws-prod-candidate`
  - AWS promotion branch
  - Receives already-tested changes from `test/localdeploy`
  - Used for coordinated AWS deployment and rollback planning

Do not start feature work directly on `bhss` or `release/aws-prod-candidate`.

## Short-Lived Branch Naming

Create new working branches from `test/localdeploy` using one of these prefixes:

- `feat/<description>`
- `fix/<description>`
- `hotfix/<description>`
- `refactor/<description>`
- `chore/<description>`
- `ops/<description>`
- `spike/<description>`

Examples:

- `feat/chat-history-chatflow-name`
- `fix/admin-batch-user-email-fallback`
- `hotfix/prod-credit-endpoints`
- `ops/prod-rollout-2026-05-04`

## Feature Workflow

Use this workflow for new feature work:

1. Create a short-lived branch from `test/localdeploy`.
2. Implement the full feature bundle on that branch.
3. Validate the touched services.
4. Merge the feature branch back into `test/localdeploy`.
5. Promote the same tested commit set to `bhss`.
6. Validate and deploy on the Windows + Docker Desktop production line.
7. Promote the same tested commit set to `release/aws-prod-candidate`.
8. Validate and deploy on AWS from `release/aws-prod-candidate`.

The rule is: develop once, promote to both production targets.

For this repo, that means feature work is authored and locally validated on the Windows workstation attached to `test/localdeploy`, using the local Docker workflow first, then the same tested commit set is promoted to `bhss` and `release/aws-prod-candidate`.

The default local development loop on this machine is:

1. create or update the feature branch from `test/localdeploy`
2. rebuild or redeploy the local stack with `python local-deploy.py`
3. validate the touched behavior against the running containers
4. merge back into `test/localdeploy` only after Docker-based local validation is acceptable

## Patch Workflow

For patching, define the patch bundle first and apply it in one pass.

1. Choose the source branch: `test/localdeploy`.
2. Inventory the exact file bundle to patch.
3. Align the whole bundle in one pass.
4. Validate the bundle.
5. Promote and deploy as one coordinated rollout.

Do not patch feature-by-feature across long-lived branches.

## Branch Hygiene

- Do not mix `test/localdeploy` and `bhss` as concurrent code sources for one feature.
- Do not re-implement the same feature separately on multiple long-lived branches.
- Treat `bhss` and `release/aws-prod-candidate` as separate production-class deployment targets with different runtime characteristics.
- Do not rename current long-lived branches in place during active work.
- If cleaner long-lived names are desired later, create new canonical branches, update automation, then retire old names gradually.

## Legacy Documentation Note

Some older documents still mention a `main`-based or trunk-based workflow. Treat this file as the current branch policy for day-to-day development and promotion.
