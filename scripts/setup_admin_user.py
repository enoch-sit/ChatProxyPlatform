"""
Creates the admin user on the live deployment.
  1. Signs up via /api/auth/signup
  2. Gets MONGODB_URI from Secrets Manager
  3. Uses SSM on the MongoDB EC2 to set role=admin, isVerified=true

Uses AWS_KEY_ID / AWS_KEY_SECRET from environment variables.
"""

import os
import json
import time
import urllib.request
import urllib.error
import boto3

# ── Credentials from non-standard env var names ──────────────────────────────
aws_key_id     = os.environ.get("AWS_KEY_ID")
aws_key_secret = os.environ.get("AWS_KEY_SECRET")

if not aws_key_id or not aws_key_secret:
    print("ERROR: AWS_KEY_ID or AWS_KEY_SECRET environment variables are not set.")
    raise SystemExit(1)

print(f"[INFO] AWS credentials loaded (key ends with ...{aws_key_id[-4:]})")

def boto(service):
    return boto3.client(
        service,
        region_name="us-east-1",
        aws_access_key_id=aws_key_id,
        aws_secret_access_key=aws_key_secret,
    )

BASE_URL = "https://aidcec-ai-agent.com"
ADMIN = {
    "username": "admin",
    "email":    "admin@aidcec.com",
    "password": "Admin@eduhkaidcec",
}

# ── Step 1: Sign up ───────────────────────────────────────────────────────────
print("\n=== Step 1: Sign up admin user ===")
payload = json.dumps(ADMIN).encode()
req = urllib.request.Request(
    f"{BASE_URL}/api/auth/signup",
    data=payload,
    headers={"Content-Type": "application/json"},
)

user_id = None
try:
    resp = urllib.request.urlopen(req)
    body = json.loads(resp.read())
    user_id = body.get("userId")
    print(f"  ✅ Created user — userId: {user_id}")
except urllib.error.HTTPError as e:
    body_text = e.read().decode()
    if "already" in body_text.lower() or e.code == 400:
        print(f"  ℹ️  User already exists ({e.code} {body_text}) — will promote via MongoDB anyway")
    else:
        print(f"  ❌ Signup failed: {e.code} {body_text}")
        raise SystemExit(1)

# ── Step 2: Get MONGODB_URI from Secrets Manager ──────────────────────────────
print("\n=== Step 2: Get MONGODB_URI from Secrets Manager ===")
sm = boto("secretsmanager")
secret_name = "/chatproxy/dev/mongodb/auth"
try:
    secret_value = sm.get_secret_value(SecretId=secret_name)
    secret_data  = json.loads(secret_value["SecretString"])
    mongo_uri    = secret_data["MONGODB_URI"]
    # Mask the password in logs
    masked = mongo_uri.split("@")[0].rsplit(":", 1)[0] + ":***@" + mongo_uri.split("@")[-1]
    print(f"  ✅ MONGODB_URI retrieved: {masked}")
except Exception as e:
    print(f"  ❌ Failed to get secret: {e}")
    raise SystemExit(1)

# ── Step 3: Promote to admin via SSM ─────────────────────────────────────────
print("\n=== Step 3: Promote user to admin via SSM → mongosh ===")
ec2 = boto("ec2")
ssm = boto("ssm")

instances = ec2.describe_instances(
    Filters=[
        {"Name": "tag:Name",                  "Values": ["chatproxy-dev-mongodb"]},
        {"Name": "instance-state-name",       "Values": ["running"]},
    ]
)
reservations = instances.get("Reservations", [])
if not reservations:
    print("  ❌ Could not find chatproxy-dev-mongodb EC2 instance")
    raise SystemExit(1)

instance_id = reservations[0]["Instances"][0]["InstanceId"]
print(f"  MongoDB EC2 instance: {instance_id}")

# Use mongo_uri directly — it already includes host, port, and credentials
# Switch the database at the end to auth_db
base_uri = mongo_uri.rstrip("/")
if "?" in base_uri:
    base_uri, params = base_uri.split("?", 1)
    conn_uri = f"{base_uri}/auth_db?{params}"
else:
    conn_uri = f"{base_uri}/auth_db"

mongo_cmd = (
    f'mongosh "{conn_uri}" --quiet --eval \''
    f'var r = db.users.updateOne('
    f'  {{username: "{ADMIN["username"]}"}}, '
    f'  {{$set: {{role: "admin", isVerified: true}}}}'
    f'); print("matched:", r.matchedCount, "modified:", r.modifiedCount);\''
)

print(f"  Running mongosh command via SSM...")
response = ssm.send_command(
    InstanceIds=[instance_id],
    DocumentName="AWS-RunShellScript",
    Parameters={"commands": [mongo_cmd]},
    TimeoutSeconds=60,
)
command_id = response["Command"]["CommandId"]
print(f"  SSM Command ID: {command_id}")

# Wait for completion
for attempt in range(1, 13):
    time.sleep(5)
    result = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
    status = result["Status"]
    if status in ("Success", "Failed", "Cancelled", "TimedOut"):
        break
    print(f"  ... waiting ({attempt}) status={status}")

print(f"  SSM Status:  {result['Status']}")
print(f"  SSM Stdout:  {result['StandardOutputContent'].strip()}")
if result["StandardErrorContent"].strip():
    print(f"  SSM Stderr:  {result['StandardErrorContent'].strip()}")

if result["Status"] != "Success":
    print("  ❌ SSM command failed — check the output above")
    raise SystemExit(1)

# ── Step 4: Verify login ──────────────────────────────────────────────────────
print("\n=== Step 4: Verify login ===")
login_payload = json.dumps({"username": ADMIN["username"], "password": ADMIN["password"]}).encode()
req = urllib.request.Request(
    f"{BASE_URL}/api/v1/chat/authenticate",
    data=login_payload,
    headers={"Content-Type": "application/json"},
)
try:
    resp = urllib.request.urlopen(req)
    body = json.loads(resp.read())
    print(f"  ✅ Login SUCCESS — role: {body.get('user', {}).get('role', 'unknown')}")
    print(f"\n{'='*50}")
    print(f"  Username : {ADMIN['username']}")
    print(f"  Password : {ADMIN['password']}")
    print(f"  Login URL: {BASE_URL}/login")
    print(f"{'='*50}")
except urllib.error.HTTPError as e:
    print(f"  ❌ Login still failing: {e.code} {e.read().decode()}")
    raise SystemExit(1)
