# Deployment And Patch Log

This folder captures the current AWS deployment status, the documented patch mechanics, and a production patch plan based on a live AWS CLI audit run from this Windows machine on 2026-05-04.

## Post-remediation update

- Production `flowise-proxy` is now deployed on candidate image `v1.0.1-d8edea2`.
- The production Flowise runtime key was re-entered and validated live through the admin APIs.
- Production Flowise admin validation is clean again: key source is `runtime`, key test returns `200`, and manual chatflow sync completes with `errors=0`.
- Production `bridge` is now deployed on candidate image `v1.0.1-d8edea2`.
- Post-deploy bridge checks succeeded: ECS service stabilized, live task definition advanced to `chatproxy-prod-bridge:2`, and `https://aidcec-ai-agent.com` returned HTTP `200`.

## What is in this folder

- `01-current-status.md` - Live status snapshot for prod and dev, plus release/aws branch observations.
- `02-deployment-mechanics.md` - How deployment and patching work in this repo today.
- `03-production-patch-plan.md` - Recommended step-by-step plan before patching prod from `release/aws`.
- `04-aws-cli-checklist.md` - Read-only AWS CLI commands for pre-checks, deploy monitoring, validation, and rollback support.
- `05-dev-flowise-proxy-error-analysis.md` - Analysis of the current dev runtime error signal seen in CloudWatch.
- `06-release-aws-scope-assessment.md` - Service-by-service scope assessment of the `release/aws` delta versus `main`.
- `07-prod-candidate-inclusion-list.md` - Concrete recommendation for what to keep, what to defer, and what is optional in a narrowed prod candidate ref.
- `08-narrowing-procedure.md` - Exact git procedure and file manifest to build a narrowed prod candidate from the current branch.
- `09-candidate-branch-status.md` - Status of the created `release/aws-prod-candidate` branch and the files currently in its worktree.
- `10-final-prod-readiness-review.md` - Final readiness assessment for committed candidate `d8edea2`.
- `11-dev-verification-checklist.md` - Exact steps to verify whether commit `d8edea2` resolves or safely bounds the dev Flowise sync issue.
- `12-prod-rollout-checklist.md` - Exact production rollout order, monitoring points, and rollback triggers for commit `d8edea2`.
- `release-aws-diff.txt` - Raw file list for `git diff --name-only main...release/aws` captured during this review.
- `narrowed-candidate-status.txt` - Raw `git status --short` snapshot for the narrowed candidate branch.
- `narrowed-candidate-tracked-diff.txt` - Raw tracked-file diff list for the narrowed candidate branch.

## Immediate conclusions

1. AWS CLI access is working on this machine against account `168437900315` in `us-east-1`.
2. The original audit found that production was ECS-stable but had a broken Flowise runtime auth path and was behind on both `flowise-proxy` and `bridge`; those two services have now been rolled forward to `v1.0.1-d8edea2` after live backend recovery.
3. Dev is not a clean promotion source yet because `flowise-proxy` shows recent runtime errors even though ECS is stable.
4. `release/aws` is broader than an AWS-only patch set right now; it includes auth, accounting, infra, local deploy, and workstation-related files in addition to `bridge` and `flowise-proxy`.
5. Production deployment exists as a dedicated manual GitHub Actions workflow, not only as an ad hoc local script.

## Intended use

Read the files in this order:

1. `01-current-status.md`
2. `02-deployment-mechanics.md`
3. `03-production-patch-plan.md`
4. `04-aws-cli-checklist.md`
5. `05-dev-flowise-proxy-error-analysis.md`
6. `06-release-aws-scope-assessment.md`
7. `07-prod-candidate-inclusion-list.md`
8. `08-narrowing-procedure.md`
9. `09-candidate-branch-status.md`
10. `10-final-prod-readiness-review.md`
11. `11-dev-verification-checklist.md`
12. `12-prod-rollout-checklist.md`
13. `release-aws-diff.txt`