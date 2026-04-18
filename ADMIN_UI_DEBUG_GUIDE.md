# Admin UI Debug Guide - v1.0.0-diagnostic

Your bridge service has been deployed with comprehensive debugging tools. Here's how to diagnose the blank admin tabs issue.

## 🔍 Quick Start (Browser Console)

1. **Open the deployed admin page**: http://chatproxy-dev-alb-1172155413.us-east-1.elb.amazonaws.com/admin
2. **Press F12** to open DevTools
3. **Go to Console tab**
4. **Paste and run this command**:

```javascript
__debugAuth.debugAuthState()
```

This will output a complete diagnostic report of:
- ✅ User object stored in browser
- ✅ Decoded JWT token (role, expiry, etc.)
- ✅ Permission check (admin role, access_admin_panel)
- ✅ Root cause analysis

## 📊 Expected Outputs

### ✅ If Authorization is Correct
```
✅ AUTH STATE LOOKS GOOD - Admin role present, token valid
   Issue is likely UI-specific (layout/tabs not rendering)
```
→ Next: Check [Troubleshooting UI Rendering Issues](#troubleshooting-ui-rendering-issues)

### ❌ If Admin Role is Missing
```
❌ ADMIN ROLE MISSING - User does not have admin role in JWT
   Next step: Promote user to admin role in auth-service database
```
→ Next: Run the [Database Role Fix](#database-role-fix)

### ❌ If Token is Expired
```
❌ TOKEN EXPIRED - Access token is no longer valid
   Next step: Re-login to get fresh token
```
→ Next: Hard refresh (Ctrl+F5) and re-login, then check auth state again

---

## 🗄️ Database Role Fix

If the auth state shows missing admin role, fix it in the auth-service database.

### Option A: PowerShell Script (Automated)

```powershell
# Check your current role (read-only)
.\scripts\check_admin_role.ps1 -Username "admin"

# Promote to admin (fixes the issue)
.\scripts\check_admin_role.ps1 -Username "admin" -FixRole
```

### Option B: MongoDB Query (Manual)

If the script doesn't work, connect to auth-service MongoDB and run:

```javascript
// Check user
db.users.findOne({username: "admin"}, {username: 1, email: 1, role: 1})

// Promote to admin
db.users.findOneAndUpdate(
  {username: "admin"},
  {$set: {role: "admin", updatedAt: new Date()}},
  {returnDocument: "after"}
)
```

### Option C: SSH to MongoDB Container

```bash
# SSH into the mongodb instance and run mongosh
ssh -i ~/.ssh/fleet_ed25519 ubuntu@10.1.1.205  # MongoDB private IP

# Run mongosh inside the container
mongosh

# Use auth database
use auth_db

# Fix the role
db.users.updateOne({username: "admin"}, {$set: {role: "admin"}})
```

**After fixing the role in database:**
1. Hard refresh browser (Ctrl+F5)
2. Re-login with your admin credentials
3. Run `__debugAuth.debugAuthState()` again to verify

---

## Troubleshooting UI Rendering Issues

If auth state looks correct but tabs are still blank:

### Check Console for Errors
1. Open DevTools (F12) → Console tab
2. Look for any red errors or warnings
3. Share any error messages with your team

### Check Network Calls
1. Open DevTools (F12) → Network tab
2. Filter by `/api/v1/admin/`
3. Click each request and check:
   - Status code (should be 200)
   - Response payload (should have data)
   - If any show 401/403/500, that's the issue

### Inspect DOM Structure
1. Open DevTools (F12) → Elements tab
2. Right-click on blank tab area → Inspect
3. Look for `<div role="tabpanel">` elements
4. Check if they contain content or are empty
5. Verify CSS flex/overflow properties are applied

### Hard Refresh to Clear Cache
1. Press **Ctrl+Shift+Delete** (or Cmd+Shift+Delete on Mac)
2. Select "All time"
3. Check "Cookies and other site data"
4. Click "Clear data"
5. Close and re-open browser

---

## 📝 Complete Debug Output Example

When you run `__debugAuth.debugAuthState()`, you should see something like:

```
🔍 ===== AUTH DEBUG STATE =====
📦 Auth Storage State: {
  hasUser: true,
  hasTokens: true,
  isAuthenticated: true
}
👤 User Object: {
  id: '507f1f77bcf86cd799439011',
  username: 'admin',
  email: 'admin@example.com',
  role: 'admin',
  permissions: [ 'manage_users', 'manage_chatflows', 'view_analytics', ... ]
}
🔐 Decoded JWT Payload: {
  sub: '507f1f77bcf86cd799439011',
  username: 'admin',
  email: 'admin@example.com',
  role: 'admin',
  issuedAt: '2026-04-18T10:30:00.000Z',
  expiresAt: '2026-04-19T10:30:00.000Z',
  isExpired: false
}
🔑 Permission Check: {
  hasAdminRole: true,
  canAccessAdmin: true,
  allPermissions: [ 'manage_users', 'manage_chatflows', ... ]
}
✅ AUTH STATE LOOKS GOOD
```

---

## 📞 Support

If after following this guide the admin tabs still don't appear:

1. **Verify user role** — Run `__debugAuth.checkRole()` (should return 'admin')
2. **Check API endpoints** — Open Network tab and look at `/api/v1/admin/*` responses
3. **Collect logs** — Open browser console, take screenshot of entire output
4. **Report issue** — Include:
   - Full `debugAuthState()` output
   - Screenshot of Network tab failed requests
   - Screenshot of DOM structure in Inspector

---

## 🔄 What Changed in This Deployment

New features added to help diagnose issues:

- **Debug utilities**: `src/utils/debugAuth.ts` - Inspects auth state, JWT, permissions
- **Global console access**: `__debugAuth.debugAuthState()` and `__debugAuth.checkRole()` 
- **Database check script**: `scripts/check_admin_role.ps1` - Diagnose and fix user roles
- **Layout fixes**: Previous session UI adjustments remain deployed

These tools are **development aids** and will be removed before production.

---

**Deployed:** April 18, 2026  
**Image**: `168437900315.dkr.ecr.us-east-1.amazonaws.com/chatproxy/bridge:v1.0.0-diagnostic`  
**Status**: Ready for debugging
