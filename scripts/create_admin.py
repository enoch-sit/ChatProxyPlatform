"""
Create first admin user for the deployed auth service.
Steps:
1. Sign up via /api/auth/signup
2. Bypass email verification via /api/testing/verify-user/:userId
3. Promote to admin via MongoDB (SSM to EC2)
"""
import json
import requests
import boto3
import time
import sys

AUTH_URL = "https://aidcec-ai-agent.com"

ADMIN = {
    "username": "admin",
    "email": "admin@aidcec.com",
    "password": "Admin@2025!",
}

print(f"=== Step 1: Sign up admin user at {AUTH_URL} ===")
try:
    r = requests.post(f"{AUTH_URL}/api/auth/signup", json=ADMIN, timeout=30)
    print(f"Status: {r.status_code}")
    print(f"Response: {r.text}")
    
    if r.status_code == 201:
        user_id = r.json().get("userId")
        print(f"✅ Created user with ID: {user_id}")
    elif r.status_code == 400 and "already" in r.text.lower():
        print("ℹ️  Admin user already exists - will still promote via MongoDB")
        user_id = None
    else:
        print(f"❌ Unexpected response, stopping.")
        sys.exit(1)
except Exception as e:
    print(f"❌ Request failed: {e}")
    sys.exit(1)

if user_id:
    print(f"\n=== Step 2: Bypass email verification ===")
    try:
        r2 = requests.post(f"{AUTH_URL}/api/testing/verify-user/{user_id}", timeout=30)
        print(f"Status: {r2.status_code}")
        print(f"Response: {r2.text}")
        if r2.status_code == 200:
            print("✅ Email verified")
        else:
            print("⚠️  Verification bypass failed, will set isVerified via MongoDB")
    except Exception as e:
        print(f"⚠️  Verify request failed: {e}")

print(f"\n=== Step 3: Promote to admin via MongoDB (SSM) ===")
ssm = boto3.client('ssm', region_name='us-east-1')
ec2 = boto3.client('ec2', region_name='us-east-1')

# Find MongoDB EC2 instance
instances = ec2.describe_instances(
    Filters=[
        {'Name': 'tag:Name', 'Values': ['chatproxy-dev-mongodb']},
        {'Name': 'instance-state-name', 'Values': ['running']}
    ]
)
instance_id = instances['Reservations'][0]['Instances'][0]['InstanceId']
print(f"MongoDB instance: {instance_id}")

mongo_cmd = f"""mongosh --quiet auth_db --eval 'db.users.updateOne({{username: "{ADMIN["username"]}"}}, {{$set: {{role: "admin", isVerified: true}}}})' """

print(f"Running: {mongo_cmd}")
response = ssm.send_command(
    InstanceIds=[instance_id],
    DocumentName='AWS-RunShellScript',
    Parameters={'commands': [mongo_cmd]},
    TimeoutSeconds=30
)

command_id = response['Command']['CommandId']
print(f"SSM Command ID: {command_id}")
time.sleep(5)

result = ssm.get_command_invocation(
    CommandId=command_id,
    InstanceId=instance_id
)
print(f"Status: {result['Status']}")
print(f"Stdout: {result['StandardOutputContent']}")
print(f"Stderr: {result['StandardErrorContent']}")

if result['Status'] == 'Success':
    print("\n✅ Admin user promoted successfully!")
    print(f"\n=== Admin Credentials ===")
    print(f"Username: {ADMIN['username']}")
    print(f"Password: {ADMIN['password']}")
    print(f"Email: {ADMIN['email']}")
else:
    print(f"\n❌ Failed to promote user. Check SSM output above.")
