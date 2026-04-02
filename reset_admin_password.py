"""
Bootstraps admin access when the admin password is unknown.

Strategy:
  1. Create a temporary admin user via the testing endpoints (no auth required)
  2. Log in as that temp admin to get a JWT
  3. List all users to find the real 'admin' user's ID
  4. Reset the 'admin' user's password to the desired value
  5. Verify the 'admin' user can now log in
  6. Clean up the temporary user

Safe to run multiple times (idempotent).
"""

import json
import time
import urllib.request
import urllib.error
import random
import string
import os

BASE_URL   = "https://aidcec-ai-agent.com"
PROXY_AUTH = f"{BASE_URL}/api/v1/chat/authenticate"
AUTH_API   = f"{BASE_URL}/api/auth"
ADMIN_API  = f"{BASE_URL}/api/admin"
TEST_API   = f"{BASE_URL}/api/testing"

TARGET_USERNAME = "admin"
TARGET_PASSWORD = os.getenv("TARGET_ADMIN_PASSWORD")

if not TARGET_PASSWORD:
    raise RuntimeError("Set TARGET_ADMIN_PASSWORD environment variable before running this script")

# ─── Helpers ────────────────────────────────────────────────────────────────

def post(url, payload, token=None):
    data = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read()) if e.read else {}

def get(url, token=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.fp.read())
        except Exception:
            body = {}
        return e.code, body

def put(url, payload, token):
    data = json.dumps(payload).encode()
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    req = urllib.request.Request(url, data=data, headers=headers, method="PUT")
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.fp.read())
        except Exception:
            body = {}
        return e.code, body

def delete(url, token):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"}, method="DELETE")
    try:
        resp = urllib.request.urlopen(req)
        return resp.status, {}
    except urllib.error.HTTPError as e:
        return e.code, {}

# ─── Step 1: Create temp bootstrap admin ────────────────────────────────────
rand_suffix   = "".join(random.choices(string.ascii_lowercase, k=6))
TEMP_USERNAME = f"bootstrap_{rand_suffix}"
TEMP_EMAIL    = f"bootstrap_{rand_suffix}@temp.invalid"
TEMP_PASSWORD = "".join(random.choices(string.ascii_letters + string.digits, k=20)) + "!A1"

print(f"\n=== Step 1: Sign up temporary admin ({TEMP_USERNAME}) ===")
code, body = post(f"{AUTH_API}/signup", {
    "username": TEMP_USERNAME,
    "email":    TEMP_EMAIL,
    "password": TEMP_PASSWORD,
})
print(f"  {code}: {body}")
if code not in (200, 201):
    print("  ❌ Signup failed")
    raise SystemExit(1)

temp_user_id = body.get("userId")
print(f"  ✅ Created temp user ID: {temp_user_id}")

# ─── Step 2: Verify + promote temp user ─────────────────────────────────────
print(f"\n=== Step 2: Verify temp user ===")
code, body = post(f"{TEST_API}/verify-user/{temp_user_id}", {})
print(f"  {code}: {body}")

print(f"\n=== Step 3: Promote temp user to admin ===")
code, body = post(f"{TEST_API}/promote-admin/{temp_user_id}", {})
print(f"  {code}: {body}")
if code != 200:
    print("  ❌ Promotion failed")
    raise SystemExit(1)

print(f"  ✅ temp user is now admin")

# ─── Step 3: Login as temp admin ────────────────────────────────────────────
print(f"\n=== Step 4: Login as temp admin ===")
code, body = post(PROXY_AUTH, {"username": TEMP_USERNAME, "password": TEMP_PASSWORD})
print(f"  {code}: {json.dumps(body)[:120]}")
if code != 200:
    print("  ❌ Login as temp admin failed")
    raise SystemExit(1)

# The proxy returns user info in 'user' key, token in 'access_token'
access_token = body.get("access_token") or body.get("accessToken")
print(f"  ✅ Got access token")

# ─── Step 4: Find the real 'admin' user ─────────────────────────────────────
print(f"\n=== Step 5: Find '{TARGET_USERNAME}' user ===")
code, body = get(f"{ADMIN_API}/users?username={TARGET_USERNAME}", token=access_token)
print(f"  {code}: {json.dumps(body)[:200]}")

admin_id = None
if code == 200:
    users = body.get("users", body.get("data", body if isinstance(body, list) else []))
    for u in users:
        if u.get("username") == TARGET_USERNAME:
            admin_id = str(u.get("_id") or u.get("id"))
            print(f"  ✅ Found admin user ID: {admin_id}")
            break

if not admin_id:
    # Try listing all users
    print("  Trying full user list...")
    code, body = get(f"{ADMIN_API}/users", token=access_token)
    print(f"  {code}: listing {len(body.get('users', body.get('data', [])) if isinstance(body, dict) else body)} users")
    users_list = body.get("users", body.get("data", body if isinstance(body, list) else []))
    for u in users_list:
        if u.get("username") == TARGET_USERNAME:
            admin_id = str(u.get("_id") or u.get("id"))
            print(f"  ✅ Found admin user ID: {admin_id}")
            break

if not admin_id:
    print(f"  ❌ Could not find user '{TARGET_USERNAME}' in the database")
    raise SystemExit(1)

# ─── Step 5: Reset the admin's password ─────────────────────────────────────
print(f"\n=== Step 6: Reset '{TARGET_USERNAME}' password ===")
code, body = put(
    f"{ADMIN_API}/users/{admin_id}/password",
    {"newPassword": TARGET_PASSWORD},
    token=access_token,
)
print(f"  {code}: {body}")
if code not in (200, 204):
    print(f"  ❌ Password reset failed")
    raise SystemExit(1)
print(f"  ✅ Password updated")

# ─── Step 6: Verify also ensure isVerified=true and role=admin ───────────────
print(f"\n=== Step 7: Ensure admin user is verified and has admin role ===")
code, body = post(f"{TEST_API}/verify-user/{admin_id}", {})
print(f"  verify-user: {code}: {body}")
code, body = post(f"{TEST_API}/promote-admin/{admin_id}", {})
print(f"  promote-admin: {code}: {body}")

# ─── Step 7: Verify login with the target credentials ───────────────────────
print(f"\n=== Step 8: Verify login as '{TARGET_USERNAME}' ===")
time.sleep(1)  # brief pause to let DB propagate
code, body = post(PROXY_AUTH, {"username": TARGET_USERNAME, "password": TARGET_PASSWORD})
print(f"  {code}: {json.dumps(body)[:200]}")
if code == 200:
    role = body.get("user", {}).get("role", "unknown") if isinstance(body.get("user"), dict) else "unknown"
    print(f"  ✅ Login SUCCESS — role: {role}")
else:
    print(f"  ❌ Login still failing — see response above")

# ─── Step 8: Clean up temp user ─────────────────────────────────────────────
print(f"\n=== Step 9: Clean up temp user ({TEMP_USERNAME}) ===")
# Demote first to be safe (make them enduser so no stray admin accounts)
code, body = put(f"{ADMIN_API}/users/{temp_user_id}/role", {"role": "enduser"}, token=access_token)
print(f"  demote: {code}: {body}")
code = delete(f"{ADMIN_API}/users/{temp_user_id}", token=access_token)
print(f"  delete: {code}")

print(f"\n{'='*50}")
print(f"  USERNAME: {TARGET_USERNAME}")
print(f"  PASSWORD: {TARGET_PASSWORD}")
print(f"  URL:      {BASE_URL}/login")
print(f"{'='*50}")
