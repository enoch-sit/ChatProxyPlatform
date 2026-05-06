# Admin Patch Test Cases (AWS First, Then Local)

## Purpose
This suite verifies the admin scrolling fix, bulk chatflow assignment reliability, and batch role update behavior.

Use these tests in this order:
1. Run all cases before patch (baseline).
2. Validate the patch bundle on `test/localdeploy`.
3. Deploy the same commit set to `bhss`.
4. Run the full admin patch suite on `bhss`.
5. Promote the same commit set to AWS production and rerun the critical smoke subset.

## Test Environment Matrix
- `test/localdeploy`: mandatory validation source before any promotion.
- `bhss`: live Windows + Docker Desktop production gate.
- AWS prod: final production rollout verification.
- Local ad hoc testing: optional support signal, not the promotion authority.

## Evidence To Capture For Every Case
- Test Case ID
- Environment
- Build or commit identifier
- Start and end timestamp
- Actual result
- Screenshot or short recording for UI cases
- Pass or Fail

## Functional Test Cases

### TC-ADM-001: Admin page loads
Preconditions:
- Admin user exists and can log in.

Steps:
1. Log in as admin.
2. Open Admin page.

Expected:
- Admin page loads without blank content.
- No visible crash banner.

### TC-ADM-002: Admin tabs are navigable
Preconditions:
- Admin page is open.

Steps:
1. Click Users tab.
2. Click Credits tab.
3. Click Usage tab.
4. Click Chat History tab.

Expected:
- Each tab renders its panel.
- No stuck state while switching tabs.

### TC-ADM-003: Users tab vertical scroll
Preconditions:
- At least 30 users exist to force list overflow.

Steps:
1. Open Users tab.
2. Scroll from top to bottom.
3. Scroll back up.

Expected:
- Scroll works smoothly.
- Header and controls remain usable.
- No clipping or frozen scroll region.

### TC-ADM-004: Credits tab vertical scroll
Preconditions:
- Credits table has enough rows to overflow.

Steps:
1. Open Credits tab.
2. Scroll down through all rows.
3. Scroll back to top.

Expected:
- Scroll works in the intended container.
- No hidden rows due to container height issues.

### TC-ADM-005: Usage tab vertical scroll
Preconditions:
- Usage data exists for many records.

Steps:
1. Open Usage tab.
2. Scroll within the table area.

Expected:
- Scroll is available and stable.
- Table remains readable.

### TC-ADM-006: Chat History panel scroll
Preconditions:
- Student chat history exists.

Steps:
1. Open Chat History tab.
2. Select a student with long history.
3. Scroll through history list and message pane.

Expected:
- Both list and message panes scroll when needed.
- No viewport cut-off.

### TC-ADM-007: Bulk chatflow assign success path
Preconditions:
- Valid chatflow exists.
- At least 5 valid user emails available.

Steps:
1. Open chatflow user assignment UI.
2. Provide 5 valid emails.
3. Run bulk assignment.

Expected:
- Operation completes with success summary.
- Users appear as assigned.

### TC-ADM-008: Bulk chatflow assign partial failure handling
Preconditions:
- Valid chatflow exists.
- Input set includes valid and invalid emails.

Steps:
1. Provide mixed input, for example 4 valid and 1 invalid email.
2. Run bulk assignment.

Expected:
- Request completes without full crash.
- Result clearly reports per-user success and failure.
- Valid users are assigned.

### TC-ADM-009: Bulk chatflow duplicate-safe behavior
Preconditions:
- Some selected users are already assigned.

Steps:
1. Include already-assigned users in the bulk input.
2. Run assignment.

Expected:
- Duplicate handling is graceful.
- Existing assignments are not corrupted.
- Response indicates duplicates or skipped rows clearly.

### TC-ADM-010: Batch role update success
Preconditions:
- At least 3 non-admin users exist.

Steps:
1. Open Users tab.
2. Select multiple users.
3. Choose new role and apply batch role update.

Expected:
- Selected users receive the new role.
- UI shows success summary.

### TC-ADM-011: Batch role update mixed validity
Preconditions:
- Selection includes at least one invalid or no-longer-existing user id.

Steps:
1. Attempt batch role update on mixed selection.

Expected:
- Endpoint returns partial success details.
- Valid users are updated.
- Invalid entries are reported, not silently ignored.

### TC-ADM-012: Authorization guard for role updates
Preconditions:
- Non-admin test user exists.

Steps:
1. Authenticate as non-admin user.
2. Attempt batch role update action (UI or API).

Expected:
- Access is denied.
- No unauthorized role changes occur.

## API Contract Test Cases

### TC-API-001: Bulk assignment response shape
Steps:
1. Call bulk assignment endpoint with mixed valid and invalid data.

Expected:
- Response includes totals and per-item result detail.
- Status and payload are consistent with frontend parsing expectations.

### TC-API-002: Batch role update response shape
Steps:
1. Call batch role update endpoint with at least 3 users.

Expected:
- Response includes updated count and per-item status.
- Error entries include reason text.

## Reliability and Regression Cases

### TC-REG-001: Repeat bulk assignment back-to-back
Steps:
1. Execute the same bulk assignment twice within one session.

Expected:
- Second run is deterministic.
- No duplicated unexpected side effects.

### TC-REG-002: Rapid tab switching under load
Steps:
1. Rapidly switch tabs 20 times while data is loaded.

Expected:
- No UI lockup.
- No visible rendering breakage.

### TC-REG-003: Browser resize responsiveness
Steps:
1. Test at desktop width.
2. Reduce width to tablet-like size.
3. Return to desktop width.

Expected:
- Scroll containers keep functioning.
- Controls remain accessible.

## AWS Platform Health Gate Cases

### TC-AWS-001: Service desired count match
Steps:
1. Run status check script action for target environment.

Expected:
- ECS running count equals desired count for critical services.

### TC-AWS-002: Endpoint health checks
Steps:
1. Verify Auth, Accounting, Chat, and Bridge endpoints.

Expected:
- All expected endpoints return success status.

### TC-AWS-003: Error and latency guardrails
Steps:
1. Run monitor action for at least 15 minutes.

Expected:
- No sustained 5xx spike.
- Latency remains within normal range.

## Exit Criteria
- All functional cases pass on `test/localdeploy` or its feature branch before promotion.
- No high-severity regression found in reliability cases.
- AWS health gate cases pass.
- The full admin suite passes on `bhss`.
- The same critical smoke subset passes on AWS prod.
- Local parity smoke tests pass when needed for investigation.

## Suggested Smoke Subset For Fast Recheck
- TC-ADM-001
- TC-ADM-003
- TC-ADM-006
- TC-ADM-008
- TC-ADM-010
- TC-AWS-001
- TC-AWS-002
