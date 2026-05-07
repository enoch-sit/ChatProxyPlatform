# Dev Verification Checklist

## Goal

Use the new admin/runtime key management surfaces in commit `d8edea2` to answer the one unresolved release question:

Can dev `flowise-proxy` successfully authenticate to Flowise for chatflow sync after key verification or key update?

## What this checklist proves

If this checklist passes, you can upgrade the current readiness decision from conditional to much stronger confidence for production.

If it fails with the same `401 Unauthorized`, the remaining risk is confirmed as still active in dev and must either be fixed or explicitly accepted before prod.

## Required access

You need one of these:

1. An admin login to the dev Bridge UI.
2. A valid elevated/admin bearer token for the dev proxy admin endpoints.

Without one of those, this exact verification cannot be executed from the repo alone.

## Target surfaces in this candidate

Bridge UI:

- `AdminPage` Settings tab
- `AdminFlowiseSettingsPanel`

Proxy endpoints:

- `GET /api/v1/admin/settings/flowise-api-key`
- `POST /api/v1/admin/settings/flowise-api-key`
- `POST /api/v1/admin/settings/flowise-api-key/test`
- `POST /api/v1/admin/chatflows/sync`

## Verification sequence

### Step 1 - Confirm deployed ref in dev

Make sure dev is actually running the intended `flowise-proxy` and `bridge` candidate or a build equivalent to it.

Record:

- current dev image tag for `flowise-proxy`
- current dev image tag for `bridge`

If dev is not on the candidate-equivalent build, the rest of the checklist is not conclusive for `d8edea2`.

### Step 2 - Open the admin settings surface

From the dev Bridge UI:

1. Sign in with an admin-capable account.
2. Open `Admin`.
3. Open the `Settings` tab.
4. Confirm the `Flowise API Key` panel loads.

Expected result:

- no panel crash
- no permissions failure for the intended admin user
- key status loads successfully

Record:

- `configured` value
- `source` value: `runtime`, `env`, or `unset`
- masked key presence

### Step 3 - Test the currently effective key

From the same settings panel:

1. Do not enter a new key yet.
2. Use `Test Key` against the effective key.

Expected success result:

- test returns valid
- HTTP status reported as `200`

Failure result of interest:

- test returns `401`

Interpretation:

- if the test already returns `200`, the current effective key is valid and the next step is to verify sync
- if the test returns `401`, the current effective key is still wrong or Flowise is rejecting it

### Step 4 - If needed, update the runtime key

Only do this if you have the correct Flowise API key value available.

From the settings panel:

1. Paste the intended Flowise API key.
2. Click `Save Key`.
3. Click `Refresh Status`.
4. Confirm source becomes `runtime`.
5. Run `Test Key` again.

Expected result:

- save succeeds
- status shows configured
- test returns `200`

### Step 5 - Trigger manual sync

After a successful key test:

1. Trigger the manual chatflow sync path.

If you are using API calls directly:

```http
POST /api/v1/admin/chatflows/sync
Authorization: Bearer <admin-token>
```

Expected result:

- sync request completes successfully
- no Flowise `401 Unauthorized` in the response path
- returned sync result does not contain `flowise_api_error`

### Step 6 - Confirm in CloudWatch

Inspect dev logs immediately after the test:

- `/ecs/chatproxy-dev-flowise-proxy`

Look for:

- success path after manual sync
- absence of fresh `Flowise API returned HTTP 401` entries for the test window

### Step 7 - Optional scheduled-sync confirmation

If you want stronger confidence:

1. Wait through one scheduled sync interval or temporarily align the interval in a dev-only test deployment.
2. Confirm the periodic sync also avoids `401`.

This is stronger than a manual sync-only result because the original problem was observed in scheduled sync.

## Pass and fail criteria

### Pass

All of these are true:

1. Settings panel loads.
2. Effective or updated key tests with `200`.
3. Manual sync succeeds.
4. No new `401` appears in the immediate validation window.

### Partial pass

These are true:

1. Key test succeeds.
2. Manual sync succeeds.
3. Scheduled sync is not yet observed.

This is still materially better evidence than you have now.

### Fail

Any of these happen:

1. Key test returns `401`.
2. Manual sync returns `flowise_api_error`.
3. CloudWatch still shows the same unauthorized sync pattern after key refresh.

## Decision after running this checklist

### If it passes

The strongest remaining blocker is removed, and the candidate becomes a substantially safer prod promotion target.

### If it fails

Do not reinterpret `d8edea2` as a sync-auth fix. Treat the candidate as operationally improved but still carrying the unresolved Flowise auth risk.

## Practical note

This checklist is the fastest path to converting the current conditional prod recommendation into a more confident go/no-go decision without widening the release scope again.