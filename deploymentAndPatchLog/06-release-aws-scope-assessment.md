# Release AWS Scope Assessment

## Source

This assessment is based on:

- `git diff --name-only main...release/aws`
- current HEAD on `release/aws`: `f9cc0d3`

The raw file list is stored in `release-aws-diff.txt`.

## High-level result

`release/aws` is not currently a narrow production patch branch.

Observed major-area counts:

| Area | Changed files |
| --- | ---: |
| `bridge` | 19 |
| `flowise-proxy-service-py` | 12 |
| `infra` | 12 |
| `accounting-service` | 6 |
| `scripts` | 4 |
| `.github` | 3 |
| `auth-service` | 2 |
| other root and workstation files | many single-file changes |

## Deployment relevance classification

### Tier 1 - Likely intended AWS app patch surface

These are the files that most directly fit the documented AWS app rollout path.

#### `bridge/**`

- Strong prod relevance.
- Directly affects the frontend artifact built by `Deploy Prod` when `service=bridge`.

#### `flowise-proxy-service-py/**`

- Strong prod relevance.
- Directly affects the backend artifact built by `Deploy Prod` when `service=flowise-proxy`.

### Tier 2 - Deploy mechanism and infrastructure surface

These do not just change application code. They can change how production is deployed or what production infrastructure expects.

#### `.github/workflows/deploy-prod.yml`

- High deployment relevance.
- Affects the prod promotion mechanism itself.

#### `.github/workflows/rollback.yml`

- High operational relevance.
- Affects rollback behavior.

#### `infra/**`

- High infrastructure relevance.
- Needs explicit sign-off before prod dispatch because even targeted Terraform applies run inside the environment shaped by these files.

#### `infra/scripts/deploy-service.ps1`

- Operator-path relevance, not GitHub Actions-path relevance.
- Important if you intend to deploy from this machine instead of only through Actions.

### Tier 3 - Other backend app changes not obviously part of a bridge/proxy-only prod patch

#### `auth-service/**`

- Runtime relevance if deployed intentionally.
- Out of scope if your prod patch is supposed to be only `bridge` and `flowise-proxy`.

#### `accounting-service/**`

- Runtime relevance if deployed intentionally.
- Same scope warning as `auth-service`.

### Tier 4 - Local, fleet, batch, probe, and workstation surfaces

Examples:

- `local-deploy.py`
- `patch.ps1`
- `patch_and_migrate.bat`
- `wg-*`
- `probe_*`
- `batch-user-create.ps1`
- `fleet-inventory.json`

These should not be treated as part of a normal ECS production patch unless you have a very specific reason.

## Practical prod candidate recommendation

### If the intended prod change is UI + proxy only

Treat the likely safe candidate scope as:

- `bridge/**`
- `flowise-proxy-service-py/**`
- `version.json` if version bumps are required
- possibly `.github/workflows/deploy-prod.yml` only if you explicitly intend to change the prod deployment workflow itself

Everything else should be split out, deferred, or explicitly approved as part of the same release.

### If the intended prod change also includes deployment mechanics

Then the candidate scope may also include:

- `.github/workflows/deploy-prod.yml`
- `.github/workflows/rollback.yml`
- the exact `infra/**` files required for that promotion path

That is a larger and riskier release class than an app-only patch.

## Recommendation

Before any production deployment, produce one of these:

1. A narrowed release ref containing only the intended prod patch files.
2. A written sign-off that explicitly includes `bridge`, `flowise-proxy-service-py`, and every additional `infra`, workflow, auth, or accounting file that will remain in scope.

## Bottom line

The present `release/aws` branch is best understood as a mixed release branch, not a clean prod promotion branch. It should be narrowed before patching production unless you deliberately want a broader release.