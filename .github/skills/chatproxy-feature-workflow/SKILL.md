---
name: chatproxy-feature-workflow
description: 'Plan and implement the next feature in ChatProxy Platform. Use when creating a new feature, choosing the right branch, validating touched services on the Windows Docker stack, and promoting the same tested commit set to bhss and release/aws-prod-candidate.'
argument-hint: 'Describe the feature and the services or user flow it touches'
user-invocable: true
disable-model-invocation: false
---

# ChatProxy Feature Workflow

## What This Skill Produces

- A repo-specific feature plan rooted in `test/localdeploy`
- A local validation plan for the touched services
- A promotion checklist for `bhss` and `release/aws-prod-candidate`

## When to Use

- Starting the next feature in this repository
- Turning a feature idea into a concrete implementation and validation workflow
- Deciding which services, tests, and deployment steps are in scope
- Preparing a tested feature bundle for Windows and AWS promotion

## Inputs to Gather

- The feature outcome in one sentence
- The services in scope: `bridge`, `auth-service`, `accounting-service`, `flowise-proxy-service-py`, or `infra`
- The user roles and end-to-end flow affected
- Whether the change touches APIs, database schema, seeds, env vars, secrets, ports, or rollout steps
- Whether the change is local-only, Windows production only, AWS only, or shared across targets

## Procedure

1. Establish the source branch.
   - Start from `test/localdeploy`.
   - Create a short-lived branch with the right prefix: `feat/`, `fix/`, `hotfix/`, `refactor/`, `chore/`, `ops/`, or `spike/`.
   - Do not author primary feature work directly on `bhss` or `release/aws-prod-candidate`.

2. Define the feature bundle.
   - Write the acceptance flow in user terms.
   - Map the controlling code path and touched services.
   - Identify shared contracts early if more than one service changes.

3. Prepare the local environment.
   - Prefer the Docker-managed local stack on the Windows workstation.
   - Use the current repo entrypoints first: `setup.ps1`, `patch.ps1`, and `diagnose.ps1`.
   - If another launcher such as `local-deploy.py` is mentioned in older docs or notes, verify it exists in the current checkout before relying on it.
   - If env vars, database credentials, seeds, or compose state changed, use a full reset that clears volumes as well as env files.

4. Implement in small vertical slices.
   - Change the deciding code path first, then wire callers and UI.
   - Keep the full feature on one short-lived branch.
   - Avoid mixing unrelated cleanup into the same feature bundle.

5. Validate the touched slice first.
   - `auth-service`: `npm test`
   - `accounting-service`: `npm test`
   - `flowise-proxy-service-py`: `pytest`
   - `bridge`: `npm run build`
   - `bridge` UI behavior: run the smallest relevant Playwright or manual flow first

6. Validate end to end against running containers.
   - Exercise the role-based path the feature changes.
   - Confirm service-to-service behavior, not just unit coverage.
   - If the change affects auth, sessions, credits, or chat history, verify the exact integration boundary that owns the behavior.

7. Update docs and rollout notes.
   - Update documentation if behavior, configuration, scripts, ports, deployment flow, or operator steps changed.
   - Call out any required secrets, migrations, or one-time setup.

8. Merge and promote.
   - Merge back into `test/localdeploy` after local Docker validation is acceptable.
   - Promote the same tested commit set to `bhss` and validate the Windows Docker production line.
   - Promote the same tested commit set to `release/aws-prod-candidate` and validate AWS-specific behavior before deployment.

## Decision Points

- UI-only change:
  - Prioritize `bridge` build plus the smallest UI test that proves the behavior.
- Backend-only change:
  - Validate the owning service first, then the caller path that consumes it.
- Cross-service contract change:
  - Validate both ends of the contract and run an end-to-end flow.
- Env, schema, or seed change:
  - Reset local state before trusting failures or passes.
- AWS-only infra or rollout change:
  - Treat local validation and promotion validation as separate concerns.

## Completion Checks

- A short-lived branch exists from `test/localdeploy`
- The acceptance flow is written and scoped
- Touched-service tests or builds pass
- Docker-based end-to-end validation is complete
- Docs or operator notes are updated when needed
- The same tested commit set is identified for `bhss` and `release/aws-prod-candidate`

## Repo Facts This Skill Assumes

- `test/localdeploy` is the development source of truth
- `bhss` is the Windows Docker production line
- `release/aws-prod-candidate` is the AWS promotion branch
- Local development should prefer the repo's Docker-managed Windows workflow
- Stale Docker volumes can invalidate auth or database validation after env resets