# BHSS Branch Sync Runbook

This runbook updates the `bhss` branch with changes from `test/localdeploy` without deleting data, resetting branches, or wiping Docker volumes.

## Purpose

Use this workflow when you want BHSS to receive shared code and deployment improvements from the main development machine while preserving BHSS-specific network and workstation settings.

Recommended direction:

- Merge `test/localdeploy` into `bhss`
- Preserve BHSS-specific values on protected files
- Validate locally before updating the BHSS workstation

## Safety Rules

- Do not use `git reset --hard`
- Do not use `git clean -fd`
- Do not force-push `bhss`
- Do not run `python local-deploy.py --reset`
- Do not delete `.env` files, `.env.local`, `.local-version`, or Docker volumes

## Protected Configuration

Treat these as BHSS-owned unless you deliberately decide otherwise during review:

- `.env` files and `.env.*` variants
- `.local-version`
- `fleet-inventory.json`
- `diagnose-bhss-state.ps1`
- `patch-windows-workstation.bat`
- `probe_and_fix_bhss.bat`
- WireGuard config and candidate files
- Any file containing BHSS host or target values such as `ai01.bhss.edu.hk`

## Phase 1: Analyze on the Main Dev Machine

From the repo root:

```powershell
.\sync-bhss-from-localdeploy.ps1
```

What this does:

- checks the git working tree
- fetches and prunes remote refs
- compares the fetched `origin/bhss` and `origin/test/localdeploy` refs
- writes a report under `logs\`
- classifies files as protected or shared candidates
- auto-flags files as protected when they match BHSS file patterns or contain BHSS target markers such as `ai01.bhss.edu.hk`

Review these before continuing:

```powershell
git log --oneline --left-right bhss...test/localdeploy
git diff --name-status bhss..test/localdeploy
git diff --name-status test/localdeploy..bhss
```

## Phase 2: Prepare the Merge Safely

Once the diff looks correct and your working tree is clean:

```powershell
.\sync-bhss-from-localdeploy.ps1 -PrepareMerge
```

What this does:

- checks out `bhss`
- fast-forwards from `origin/bhss`
- creates a backup branch named like `backup/bhss-before-test-localdeploy-YYYYMMDD`
- runs `git merge --no-ff --no-commit origin/test/localdeploy`
- attempts to keep the `bhss` version of protected files, including BHSS-targeted files detected by content markers

After the script finishes, inspect the prepared merge manually:

```powershell
git status --short
git diff --cached
git diff
```

If the prepared merge contains localhost-only config from `test/localdeploy`, keep the `bhss` side for those files.

## Phase 3: Validate Before Commit

Run only non-destructive checks from the main dev machine:

```powershell
python local-deploy.py --status
powershell -ExecutionPolicy Bypass -File .\diagnose.ps1 -Quick
```

If the branch diff only touched a subset of services, validate those services first rather than widening scope.

When satisfied, commit the merge manually:

```powershell
git commit -m "Merge test/localdeploy into bhss with BHSS config preserved"
git push origin bhss
```

## Phase 4: Update the BHSS Workstation

On BHSS, start with preflight checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\diagnose-bhss-state.ps1
```

If you are on the management machine and using WireGuard SSH:

```powershell
.\fleet.ps1 -Action health -Target BHSS-AI-SERVER01
```

Confirm BHSS is on branch `bhss` and can fast-forward cleanly. If BHSS has local commits, stop and reconcile them before deployment.

## Phase 5: Deploy Only What Changed

Preferred path on BHSS:

```powershell
set PATCH_TARGET=BHSS
set PATCH_ALLOW_ALL=1
patch-windows-workstation.bat all auto
```

If only one service changed, patch only that service instead of all services.

For bridge changes, confirm the build target still points to BHSS:

```powershell
set FLOWISE_PROXY_URL=http://ai01.bhss.edu.hk:8000
```

If triggering remotely from the management machine:

```powershell
.\fleet.ps1 -Action patch -Target BHSS-AI-SERVER01 -PatchMode auto
```

## Phase 6: Post-Deploy Validation

Run the BHSS diagnostics again:

```powershell
powershell -ExecutionPolicy Bypass -File .\diagnose-bhss-state.ps1
powershell -ExecutionPolicy Bypass -File .\probe-bridge-target.ps1 -PreferredHost "ai01.bhss.edu.hk" -ProxyPort 8000
```

Verify:

- expected containers are running
- localhost health endpoints respond
- BHSS bridge points at the correct flowise-proxy target
- no BHSS hostname or network config was replaced with localhost values

## Recovery

If the merge result is wrong before commit:

```powershell
git merge --abort
git checkout bhss
```

If the merge was committed and later fails validation, revert the merge commit or redeploy from the backup branch created during merge preparation.

Use revert, not reset:

```powershell
git revert -m 1 <merge-commit-sha>
git push origin bhss
```

Then redeploy via the normal BHSS patch path.