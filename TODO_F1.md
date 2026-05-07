# TODO F1: Add Chatflow Name To Admin Chat History

Use this plan to implement and promote the feature that shows the chatflow name in admin chat history, using `TODO.md` as the workflow template and using this Windows workstation as the Docker-first `test/localdeploy` development machine.

## Feature Goal

Add chatflow name to the admin chat history view so admins can identify which course or chatflow a session belongs to when reviewing a student's history.

## Product Understanding

The intended user outcome is broader than just adding one more field to a message payload.

What the admin should be able to do:

- understand which chatflow or course a student session belongs to
- view student chat history with chatflow context, not just raw session metadata
- use chatflow name as part of how sessions are identified in the admin workflow

What this most likely means in the UI:

- show chatflow name in the session list if the session metadata can support it
- show chatflow name again in the selected history header or session details area
- keep the admin workflow readable even when topic or session id is unclear

Important clarification:

- the feature is not only about showing chatflow name inside already-opened messages
- the stronger product goal is to let admins review student chat history by chatflow or course context
- an optional stretch improvement would be filtering or grouping sessions by chatflow name, but that is not required for the first increment

## Current Implementation Anchors

Primary implementation areas already in the repo:

- `bridge/src/components/admin/AdminChatHistoryPanel.tsx`
- `bridge/src/api/admin.ts`
- `bridge/src/utils/chatParser.ts`
- `flowise-proxy-service-py/app/api/admin.py`
- `flowise-proxy-service-py/tests/test_admin_chat_history.py`

Related chatflow surfaces that may help with naming or lookup:

- `bridge/src/types/chatflow.ts`
- `bridge/src/api/admin.ts` chatflow APIs
- `bridge/src/locales/en/translation.json`
- `bridge/src/locales/zh-Hans/translation.json`
- `bridge/src/locales/zh-Hant/translation.json`

## Working Hypothesis

The admin history endpoint currently returns enough session or message history to render the conversation, but not the chatflow display name in a form the admin chat history panel can show directly. The smallest reliable feature path is:

1. extend the admin session and or history backend response to include chatflow metadata or chatflow name
2. update the bridge admin API type and parser path to preserve that field
3. render the chatflow name in the session list and or selected history header
4. add focused tests for the backend response and the admin UI behavior

## Workflow Pipeline

### 1. Create the feature branch

- Start from `test/localdeploy`
- Create a short-lived branch such as `feat/admin-chat-history-chatflow-name`
- Do not start feature work on `bhss` or `release/aws-prod-candidate`

### 2. Confirm the data source for chatflow name

- Inspect `flowise-proxy-service-py/app/api/admin.py` admin history route
- Identify whether chatflow name can be read directly from session documents, message documents, or a related chatflow collection
- Decide on the response shape for the admin history endpoint
- Keep the response change minimal and backward-compatible where possible

### 3. Implement backend support

- Update the admin history route in `flowise-proxy-service-py/app/api/admin.py`
- Return chatflow metadata needed by the UI, ideally including both ID and display name if available
- Avoid changing unrelated admin history fields
- Keep environment-specific config untouched

### 4. Add backend tests

- Extend or add focused tests in `flowise-proxy-service-py/tests/test_admin_chat_history.py`
- Verify the admin history endpoint returns chatflow name when present
- Verify behavior when chatflow name is missing or cannot be resolved
- Keep the test narrow to the admin history slice

### 5. Update bridge API handling

- Update `bridge/src/api/admin.ts` to accept the enhanced admin history response
- Preserve the new field through any response mapping
- Update `bridge/src/utils/chatParser.ts` only if the current mapping path drops the new field
- Avoid widening changes into unrelated chat or session flows

### 6. Update admin UI

- Update `bridge/src/components/admin/AdminChatHistoryPanel.tsx`
- Display the chatflow name in a clear place for admins, such as near the selected session details or history header
- If needed, add i18n strings for the new label in the locale files
- Keep the UI change readable on desktop and existing admin layout constraints

### 7. Validate on the feature branch

- Run focused backend tests for admin chat history
- Run focused bridge tests if available for the touched slice
- Run build or typecheck for `bridge`
- Smoke test the admin chat history flow locally:
  - select a user
  - select a session
  - verify chatflow name is visible
  - verify existing history rendering still works

## `test/localdeploy` Development And Local Deploy Plan

Use this section while the feature is still being built and verified before promotion to `bhss` or AWS.

### Local development goal

- Build and verify the feature on this Windows workstation before promoting it anywhere else
- Use the Docker-managed local stack as the default development path for this feature on this machine
- Implement and verify the feature completely on `test/localdeploy`
- Confirm the admin history backend contract and bridge UI are aligned before any production-class promotion
- Keep config changes out of scope unless the feature cannot run without them

### Expected development surfaces

- `flowise-proxy-service-py/app/api/admin.py`
- `flowise-proxy-service-py/tests/test_admin_chat_history.py`
- `bridge/src/api/admin.ts`
- `bridge/src/components/admin/AdminChatHistoryPanel.tsx`
- `bridge/src/utils/chatParser.ts`
- locale files only if a new admin label is added

### Local development loop

1. update the backend response first
2. add or update focused backend tests
3. update the bridge API typing or mapping layer
4. update the admin chat history panel
5. rebuild or redeploy the local Docker stack with `python local-deploy.py` or the narrowest required container rebuild path
6. run focused validation
7. smoke test the admin workflow locally through the running containers

### Suggested local validation sequence

Backend:

- run the focused admin history tests in `flowise-proxy-service-py/tests/test_admin_chat_history.py`
- confirm the admin history response includes chatflow name or chatflow metadata in the expected shape

Bridge:

- run bridge build or typecheck
- run focused UI tests if available for the admin chat history slice
- verify the admin panel renders the new field without breaking session or message display

Manual local smoke check:

- use the Docker-hosted local services on this machine, not an ad hoc host-only run
- sign in as admin
- open Admin > Student Chats
- choose a user and session
- confirm chatflow name is visible in the history view
- confirm sessions without resolvable chatflow name still render cleanly
- confirm no regression in loading state, session switching, or message rendering

### Local deploy expectation on `test/localdeploy`

- Treat this Windows machine as the local integration environment for `test/localdeploy`
- Prefer the repo's Docker-first workflow via `python local-deploy.py`
- keep the feature deployable in the local development environment before promotion
- if Docker-based local deploy is used, rebuild only the touched services
- if only frontend or backend code changed, avoid unnecessary full-environment churn

Suggested local deploy targets for this feature:

- `flowise-proxy-service-py`
- `bridge`

### Pre-promotion gate from `test/localdeploy`

Do not promote this feature until all of the following are true:

- backend contract is stable
- bridge typecheck or build passes
- focused tests pass for the touched slice
- local admin smoke test passes
- no environment-specific config changes were mixed into the feature by accident

### 8. Merge into `test/localdeploy`

- Open a PR into `test/localdeploy`
- Merge only after the feature bundle is validated end-to-end
- Treat `test/localdeploy` as the single development source of truth

### 9. Promote the same commit set to `bhss`

- Promote the already-tested commit set from `test/localdeploy` to `bhss`
- Promote feature code only, not BHSS-specific config
- Do not overwrite `.env`, Docker Desktop-specific runtime config, or workstation settings

Safer promotion paths for BHSS:

```powershell
git restore --source test/localdeploy --worktree -- bridge/src flowise-proxy-service-py/app flowise-proxy-service-py/tests
```

Or, if the feature commits are clean and isolated:

```powershell
git cherry-pick <feature-commit-sha>
```

### 10. Validate on `bhss`

- Verify admin chat history loads correctly
- Verify the chatflow name is visible for expected sessions
- Verify no regression in session selection or message rendering
- Check for Windows or Docker Desktop specific runtime differences
- If `bhss` fails, fix the issue on `test/localdeploy`, then re-promote

### 11. Promote the same commit set to AWS

- Promote the same tested commit set to `release/aws-prod-candidate`
- Do not overwrite AWS config such as `infra/environments/prod/terraform.tfvars`, secrets, or deployment metadata unless the feature truly requires it
- Keep AWS promotion focused on application code

### 12. Validate on AWS

- Deploy from `release/aws-prod-candidate`
- Run the AWS smoke checks for the admin chat history feature
- Confirm the chatflow name appears in the same place and format as the validated `bhss` version
- If AWS exposes a feature issue, fix it on `test/localdeploy` first, then re-promote through `bhss` and AWS

## Rules

- Author the feature once on `test/localdeploy`
- Promote the same commit set to both production targets
- Do not use `bhss` and AWS as separate development branches
- Do not mix feature code and environment-specific config unless required
- Keep the backend response change as small as possible
- Prefer adding explicit tests around the admin history contract before broad UI refactors

## Quick Branch Flow

1. `test/localdeploy` -> create `feat/admin-chat-history-chatflow-name`
2. implement backend response and UI display
3. validate locally and with focused tests
4. merge into `test/localdeploy`
5. promote same commit set to `bhss`
6. validate on `bhss`
7. promote same commit set to `release/aws-prod-candidate`
8. validate on AWS

## Done Criteria

- Admin chat history shows chatflow name for sessions where it is available
- Existing admin history behavior still works
- Backend contract is covered by focused tests
- Bridge build or typecheck passes
- Feature is validated on `test/localdeploy`, `bhss`, and AWS

## Reference Docs

- `TODO.md`
- `docs/BRANCHING_POLICY.md`
- `docs/PATCH_QUICK_REFERENCE.md`
- `docs/BRANCH_PROTECTION_CHECKLIST.md`
