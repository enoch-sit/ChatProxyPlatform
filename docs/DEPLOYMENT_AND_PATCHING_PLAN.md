# Systematic Deployment & Patching Plan

> Historical planning note: the branch model described in this document predates the current repository workflow. Use [BRANCHING_POLICY.md](BRANCHING_POLICY.md) as the source of truth for current branch roles and promotion flow.

## Problem Statement

Two distinct but related problems:

1. **AWS Deployment** — Manual, error-prone, no CI/CD, bridge requires special handling, ad-hoc image tags, no rollback safety net
2. **Windows Workstation Patching** — 15+ scripts in repo root, no version pinning, no selective rollback, no way to push updates to multiple machines simultaneously

---

## Current State Summary

| Area | What Exists | Gap |
| ---- | ----------- | --- |
| AWS Deploy | `deploy-service.ps1` builds/pushes/applies per-service | No CI/CD trigger, no gated promotion, bridge bypasses terraform |
| Image Tagging | Ad-hoc (`debug-batch-f7d02e9`, `scroll-fix-f7d02e9`, `latest`) | No semantic versioning, can't tell what's deployed |
| Rollback | Can re-deploy old tag manually | No automated rollback on health-check failure |
| Local Setup | `quick_install.bat` → `automated_setup.py` chain | Works but fragile, no idempotency checks |
| Local Patching | `update_patch.bat` does `git pull` + `docker compose up` | No version pinning, no selective service update, no rollback |
| CI/CD | PATCHING_STRATEGY.md describes GitHub Actions flow | **Not implemented** — `.github/workflows/` doesn't exist |
| Bridge Deploy | Must manually register task def + `aws ecs update-service` | `ignore_changes = [task_definition]` in terraform |

---

## Plan Overview

Three phases, each independently valuable:

```text
Phase 1: Foundation        Phase 2: CI/CD Pipeline     Phase 3: Fleet Management
(1-2 days)                 (2-3 days)                  (1-2 days)
─────────────────          ──────────────────          ──────────────────
• Git branching model      • GitHub Actions workflows  • Workstation registry
• Semantic versioning      • Automated build + push    • Central version manifest
• Release tagging          • Gated deploy to dev       • Smart local updater
• Fix bridge terraform     • Slack/Teams notifications • Health reporting
• Unified deploy script    • Rollback automation       • Remote patch trigger
```

---

## Phase 1: Foundation (Git + Versioning + Scripts)

### 1.1 — Git Branching Model

This section is superseded by [BRANCHING_POLICY.md](BRANCHING_POLICY.md).

Current working model:

- `test/localdeploy` = development source of truth
- `bhss` = live Windows + Docker Desktop production branch
- `release/aws-prod-candidate` = AWS promotion branch
- short-lived working branches = `feat/...`, `fix/...`, `hotfix/...`, `refactor/...`, `chore/...`, `ops/...`, `spike/...`

Use the current branch policy document for operational decisions and branch hygiene.

### 1.2 — Semantic Versioning

Introduce a single version source at the repo root:

```json
// version.json (repo root)
{
  "version": "1.0.0",
  "services": {
    "auth-service":      "1.0.0",
    "accounting-service": "1.0.0",
    "flowise-proxy":     "1.0.0",
    "bridge":            "1.0.0"
  }
}
```

**Image tag format:** `v{version}-{short-sha}` → e.g., `v1.2.0-a3f8b21`

- Readable (version tells you the release)
- Traceable (SHA tells you the exact commit)
- Sortable (semver prefix enables easy comparison)

**Bump workflow:**

```powershell
# bump-version.ps1 — bumps version.json + creates git tag
.\infra\scripts\bump-version.ps1 -Service auth-service -Type patch
# Result: auth-service 1.0.0 → 1.0.1, creates tag v1.0.1-auth
```

### 1.3 — Fix Bridge Terraform Lifecycle

The `ignore_changes = [task_definition]` on bridge-ecs was added to prevent terraform from reverting manual deploys. The real fix:

**Option A (Recommended):** Remove `ignore_changes` and always deploy via terraform:

```hcl
# infra/modules/bridge-ecs/main.tf
lifecycle {
  ignore_changes = [desired_count]  # keep this — autoscaling
  # REMOVED: task_definition — now terraform manages it
}
```

This works because `deploy-service.ps1` already updates `terraform.tfvars` with the new image tag before running `terraform apply`. The cycle that caused the original problem was:

1. Manual deploy → terraform.tfvars not updated → next `terraform apply` reverts
2. Fix: `deploy-service.ps1` updates tfvars first → no revert

**Option B (If A causes issues):** Keep `ignore_changes` but add a dedicated bridge deploy step to `deploy-service.ps1` that uses `aws ecs register-task-definition` + `update-service` as a fallback.

### 1.4 — Unified Deploy Script (enhance existing deploy-service.ps1)

Enhance `deploy-service.ps1` to handle all services uniformly:

```powershell
# Current (works for auth, accounting, flowise-proxy):
.\infra\scripts\deploy-service.ps1 -Service auth-service -Tag v1.0.0

# Enhanced — add these capabilities:
-DryRun           # Show what would happen without doing it
-Rollback         # Revert to previous task definition revision
-HealthTimeout 300 # Wait N seconds for healthy (default 300)
-AutoRollback     # If health check fails, revert automatically
-All              # Deploy all services in dependency order
```

**Dependency order:** auth-service → accounting-service → flowise-proxy → bridge

**Auto-rollback logic:**

```text
1. Record current task definition revision before deploy
2. Deploy new revision
3. aws ecs wait services-stable --timeout 300
4. If timeout/failure → re-deploy saved revision
5. Exit with error code + log
```

### 1.5 — Commit terraform.tfvars Changes

`deploy-service.ps1` modifies `terraform.tfvars` but doesn't commit. Add:

```powershell
# At end of deploy-service.ps1, after successful deploy:
git add infra/environments/dev/terraform.tfvars
git commit -m "deploy($Service): $Tag"
git push origin release/aws-prod-candidate
```

This eliminates state drift between the repo and what's actually deployed.

---

## Phase 2: CI/CD Pipeline (GitHub Actions)

### 2.1 — Workflow Structure

The workflow names below are historical examples. In the current branch policy, the triggering branch should be the configured promotion branch rather than a hardcoded feature or trunk branch.

```text
.github/
  workflows/
    ci.yml              # PR checks: lint, test, type-check, docker build (no push)
    deploy-dev.yml      # On push to configured promotion branch OR manual trigger: build + push + deploy
    deploy-service.yml  # Manual: deploy single service with specific tag
    rollback.yml        # Manual: rollback a service to previous revision
```

### 2.2 — CI Workflow (ci.yml)

Runs on every PR to the configured integration or promotion branch:

```yaml
name: CI
on:
  pull_request:
    branches: [test/localdeploy]

jobs:
  changes:
    # Detect which services changed (paths filter)
    outputs:
      auth: ${{ steps.filter.outputs.auth }}
      accounting: ${{ steps.filter.outputs.accounting }}
      proxy: ${{ steps.filter.outputs.proxy }}
      bridge: ${{ steps.filter.outputs.bridge }}
      infra: ${{ steps.filter.outputs.infra }}

  test-auth:
    needs: changes
    if: needs.changes.outputs.auth == 'true'
    steps:
      - npm ci && npm run lint && npm test
      - docker build ./auth-service  # build-only, no push

  test-accounting:
    needs: changes
    if: needs.changes.outputs.accounting == 'true'
    steps:
      - npm ci && npm run lint && npm test
      - docker build ./accounting-service

  test-proxy:
    needs: changes
    if: needs.changes.outputs.proxy == 'true'
    steps:
      - pip install -r requirements.txt && pytest
      - docker build ./flowise-proxy-service-py

  test-bridge:
    needs: changes
    if: needs.changes.outputs.bridge == 'true'
    steps:
      - npm ci && npx tsc --noEmit
      - docker build ./bridge

  terraform-plan:
    needs: changes
    if: needs.changes.outputs.infra == 'true'
    steps:
      - terraform init && terraform plan  # plan only, no apply
```

### 2.3 — Deploy Workflow (deploy-dev.yml)

Runs on push to the configured AWS promotion branch (only changed services):

```yaml
name: Deploy Dev
on:
  push:
    branches: [release/aws-prod-candidate]
  workflow_dispatch:
    inputs:
      services:
        description: 'Comma-separated services to deploy (or "all")'
        default: 'all'

env:
  AWS_REGION: us-east-1
  ECR_REGISTRY: 168437900315.dkr.ecr.us-east-1.amazonaws.com

jobs:
  detect-changes:
    # Same path-filter as CI

  deploy-service:
    needs: detect-changes
    strategy:
      max-parallel: 1  # Deploy sequentially
      matrix:
        service: [auth-service, accounting-service, flowise-proxy, bridge]
    steps:
      - name: Build & Push
        run: |
          TAG="v$(jq -r '.services["${{ matrix.service }}"]' version.json)-${GITHUB_SHA::7}"
          docker build -t $ECR_REGISTRY/chatproxy/${{ matrix.service }}:$TAG ./${{ matrix.service }}
          docker push $ECR_REGISTRY/chatproxy/${{ matrix.service }}:$TAG

      - name: Update tfvars
        run: |
          # Update terraform.tfvars with new image tag
          # Commit back to the AWS promotion branch if your workflow requires tracked tfvars

      - name: Terraform Apply
        run: |
          cd infra/environments/dev
          terraform init -backend-config=backend.hcl
          terraform apply -auto-approve -target=module.${{ matrix.service }}_ecs

      - name: Wait for Stable
        run: |
          aws ecs wait services-stable --cluster chatproxy-dev-cluster \
            --services chatproxy-dev-${{ matrix.service }}

      - name: Health Check
        run: |
          # Hit /health endpoint, verify 200
          # If failed → trigger rollback job
```

### 2.4 — GitHub Actions Secrets Required

```text
AWS_ACCESS_KEY_ID          # IAM user or OIDC role for GitHub Actions
AWS_SECRET_ACCESS_KEY      # (prefer OIDC role assumption instead)
AWS_ACCOUNT_ID             # 168437900315
```

**Recommended:** Use [OIDC federation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) instead of long-lived credentials.

### 2.5 — Manual Rollback Workflow (rollback.yml)

```yaml
name: Rollback
on:
  workflow_dispatch:
    inputs:
      service:
        description: 'Service to rollback'
        required: true
        type: choice
        options: [auth-service, accounting-service, flowise-proxy, bridge]
      revision:
        description: 'Task definition revision (blank = previous)'

jobs:
  rollback:
    steps:
      - name: Get previous revision
        # aws ecs describe-services → current task def → subtract 1
      - name: Update service
        # aws ecs update-service --task-definition <revision>
      - name: Wait stable
      - name: Update tfvars to match rolled-back image
```

---

## Phase 3: Windows Workstation Fleet Management

### 3.1 — Problem

Multiple Windows workstations need:

- Initial setup (Docker, Node, Python, Git, services, secrets)
- Ongoing patches (code updates, config changes, new services)
- Consistency (all machines on same version)
- Visibility (which machine runs what version)

### 3.2 — Workstation Registry (version manifest)

Create a central manifest that workstations check:

```json
// workstation-manifest.json (in repo root, updated by CI)
{
  "currentVersion": "1.2.0",
  "minimumVersion": "1.0.0",
  "releaseDate": "2026-04-17",
  "services": {
    "auth-service":       { "version": "1.2.0", "image": "chatproxy/auth-service:v1.2.0-a3f8b21" },
    "accounting-service": { "version": "1.2.0", "image": "chatproxy/accounting-service:v1.2.0-a3f8b21" },
    "flowise-proxy":      { "version": "1.2.0", "image": "chatproxy/flowise-proxy:v1.2.0-a3f8b21" },
    "bridge":             { "version": "1.2.0", "image": "chatproxy/bridge:v1.2.0-a3f8b21" }
  },
  "changelog": [
    { "version": "1.2.0", "date": "2026-04-17", "changes": ["Fix table scroll in admin dashboard", "Clean up debug logging"] },
    { "version": "1.1.0", "date": "2026-04-10", "changes": ["Add batch user creation", "Credit management panel"] }
  ],
  "requiredTools": {
    "docker": ">=24.0.0",
    "node": ">=18.0.0",
    "python": ">=3.11.0",
    "git": ">=2.40.0"
  }
}
```

### 3.3 — Smart Updater Script (replaces update_patch.bat)

A single `patch.ps1` that handles everything:

```text
patch.ps1
├── Check current version (local version.json vs remote manifest)
├── If behind:
│   ├── Show changelog of what's new
│   ├── git pull (or git checkout <tag> for pinned version)
│   ├── Diff which services changed
│   ├── Rebuild only changed services
│   ├── Rolling restart (one service at a time)
│   ├── Health check each service
│   ├── Update local version marker
│   └── Report success/failure
└── If current: "Already up to date"
```

**Key improvements over `update_patch.bat`:**

- **Selective rebuild** — Only rebuilds services that changed (saves 5-10 min)
- **Rolling restart** — Restarts services one at a time, not all at once
- **Health gating** — Won't proceed to next service if current one fails health check
- **Version tracking** — Writes `.local-version` file so you always know what's running
- **Rollback** — `patch.ps1 -Rollback` reverts to previous git tag + restarts

### 3.4 — Consolidate Root Scripts

Current state: 15+ `.bat`/`.ps1` files in repo root. Consolidate into a single entry point:

```text
KEEP (rename/move):
  setup.ps1              ← consolidated from quick_install.bat + automated_setup.bat + automated_setup.py
  patch.ps1              ← consolidated from update_patch.bat + patch_local.ps1
  diagnose.ps1           ← consolidated from diagnose_setup.bat + check_system.bat + post-installation-check.bat
  infra/scripts/         ← all AWS scripts stay here (deploy, start, stop, etc.)

ARCHIVE (move to scripts/archive/):
  All individual .bat files that are now consolidated
  One-off diagnostic/fix scripts
```

### 3.5 — Multi-Machine Rollout Strategy

For pushing updates to N workstations:

#### Option A: Git Tag + Scheduled Check (Simple)

```text
1. Developer merges to test/localdeploy, then tags v1.2.0 after promotion approval
2. Each workstation has a scheduled task running daily:
   - git fetch --tags
   - Compare local version vs latest tag
   - If behind: auto-run patch.ps1 (or notify user)
3. Machines self-update overnight
```

#### Option B: Central Dashboard (More Control)

```text
1. Each workstation reports its version to a shared endpoint:
   POST /api/workstation-status { machine: "LAB-PC-01", version: "1.1.0", services: {...} }
2. Admin dashboard shows fleet status:
   LAB-PC-01: v1.1.0 (BEHIND) | LAB-PC-02: v1.2.0 (CURRENT) | ...
3. Admin can trigger remote update via:
   - Shared folder signal file (\\fileserver\patches\trigger-v1.2.0.flag)
   - Or simple webhook if machines have network access
```

**Recommendation:** Start with Option A (simple, no infrastructure needed). Move to Option B only if managing 10+ machines.

---

## Implementation Priority

| # | Task | Effort | Impact | Dependency |
| --- | ---- | ------ | ------ | ---------- |
| 1 | Create `version.json` + image tag convention | 30 min | High | None |
| 2 | Fix bridge-ecs `ignore_changes` | 30 min | High | None |
| 3 | Enhance `deploy-service.ps1` with auto-rollback | 2 hr | High | #1 |
| 4 | Add tfvars auto-commit to deploy script | 30 min | Medium | #3 |
| 5 | Create `.github/workflows/ci.yml` | 2 hr | High | None |
| 6 | Create `.github/workflows/deploy-dev.yml` | 3 hr | High | #1, #5 |
| 7 | Create `workstation-manifest.json` | 30 min | Medium | #1 |
| 8 | Write `patch.ps1` (smart updater) | 3 hr | High | #7 |
| 9 | Write `setup.ps1` (consolidated installer) | 2 hr | Medium | None |
| 10 | Write `diagnose.ps1` (consolidated diagnostics) | 1 hr | Low | None |
| 11 | Create rollback workflow | 1 hr | Medium | #6 |
| 12 | Add scheduled update check for workstations | 1 hr | Medium | #8 |

**Start with: #1 → #2 → #5 → #6 → #8** — This gives you versioning, CI, automated deploy, and local patching.

---

## Decision Points (Need Your Input)

1. **Bridge terraform fix** — Remove `ignore_changes = [task_definition]`? Or keep the manual workaround?
2. **GitHub Actions vs other CI** — GitHub Actions assumed (free for public repos, cheap for private). Any preference for AWS CodePipeline, Jenkins, etc.?
3. **Auto-deploy on push to the promotion branch?** — Or require manual trigger (safer but more friction)?
4. **Workstation auto-update overnight?** — Or always require manual `patch.ps1` run?
5. **How many workstations?** — Determines whether simple git-tag approach or central dashboard is needed.
