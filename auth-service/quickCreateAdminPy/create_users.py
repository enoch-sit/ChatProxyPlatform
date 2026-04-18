#!/usr/bin/env python3
"""
User Management Script for Simple Authentication System
This script creates an admin user, promotes it to admin role, and uses it to create supervisors and regular users.
"""

import json
import requests
import subprocess
import time
import sys
import os
import datetime

# Configuration
API_BASE_URL = "http://localhost:3000"
MONGODB_CONTAINER = "mongodb-auth"
ADMIN_USER = {
    "username": "admin",
    "email": "admin@example.com",
    "password": "admin@admin",
}
SUPERVISOR_USERS = [
    {
        "username": "supervisor1",
        "email": "supervisor1@example.com",
        "password": "Supervisor1@",
        "role": "supervisor",
    },
    {
        "username": "supervisor2",
        "email": "supervisor2@example.com",
        "password": "Supervisor2@",
        "role": "supervisor",
    },
]
REGULAR_USERS = [
    {
        "username": "user1",
        "email": "user1@example.com",
        "password": "User1@123",
        "role": "enduser",
    },
    {
        "username": "user2",
        "email": "user2@example.com",
        "password": "User2@123",
        "role": "enduser",
    },
]

# Log file setup
LOG_FILE = "user_credentials.log"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_PATH = os.path.join(SCRIPT_DIR, LOG_FILE)


def log_user_creation(user_type, username, email, password, user_id=None):
    """Log user creation details to file"""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] Created {user_type}: username='{username}', email='{email}', password='{password}'"
    if user_id:
        log_entry += f", id='{user_id}'"

    with open(LOG_PATH, "a") as log_file:
        log_file.write(log_entry + "\n")

    # Don't print passwords to console for security
    console_entry = (
        f"[{timestamp}] Created {user_type}: username='{username}', email='{email}'"
    )
    if user_id:
        console_entry += f", id='{user_id}'"

    print(f"✓ Log entry created: {console_entry}")


def run_command(command):
    """Run a shell command and return the output"""
    try:
        result = subprocess.run(
            command,
            shell=True,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Command failed with error: {e}")
        print(f"Error output: {e.stderr}")
        return None


def check_api_health():
    """Check if the API server is running"""
    try:
        print(f"Checking API health at {API_BASE_URL}/health...")
        response = requests.get(f"{API_BASE_URL}/health", timeout=10)
        print(f"API response status: {response.status_code}")
        if response.status_code == 200:
            print("✅ API server is running")
            return True
    except requests.RequestException as e:
        print(f"❌ API connection error: {e}")

    print("❌ API server is not running. Please start the Docker environment first.")
    print("Run: docker-compose -f docker-compose.dev.yml up -d")
    return False


def create_admin_user():
    """Create the admin user through the API"""
    print("\n--- Creating admin user ---")
    try:
        response = requests.post(f"{API_BASE_URL}/api/auth/signup", json=ADMIN_USER)
        if response.status_code == 201:
            data = response.json()
            user_id = data.get("userId")
            print(f"✅ Admin user created with ID: {user_id}")
            # Log the admin user creation
            log_user_creation(
                "Admin",
                ADMIN_USER["username"],
                ADMIN_USER["email"],
                ADMIN_USER["password"],
                user_id,
            )
            return user_id
        else:
            print(f"❌ Failed to create admin user: {response.text}")
            if response.status_code == 400 and "already exists" in response.text:
                print("ℹ️ Admin user might already exist, continuing...")
                # Log attempt with note that user might already exist
                log_user_creation(
                    "Admin (possible existing)",
                    ADMIN_USER["username"],
                    ADMIN_USER["email"],
                    ADMIN_USER["password"],
                )
                return "existing"
    except requests.RequestException as e:
        print(f"❌ Request error: {e}")

    return None


def promote_to_admin():
    """Connect to MongoDB and promote the admin user to admin role"""
    print("\n--- Promoting user to admin role ---")
    # Get the directory where the script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    mongo_file_path = os.path.join(script_dir, "mongo_commands.js")

    mongo_commands = f"""use auth_db
db.users.updateOne({{ username: "{ADMIN_USER['username']}" }}, {{ $set: {{ role: "admin", isVerified: true }} }})
exit
"""

    # Write MongoDB commands to a temporary file
    with open(mongo_file_path, "w") as f:
        f.write(mongo_commands)

    # Execute MongoDB commands
    command = f'docker exec -i {MONGODB_CONTAINER} mongosh < "{mongo_file_path}"'
    output = run_command(command)

    # Check for various possible output patterns
    if output and (
        "matchedCount: 1" in output
        or 'matchedCount" : 1' in output
        or "modifiedCount: 1" in output
        or 'modifiedCount" : 1' in output
    ):
        print("✅ User promoted to admin role successfully")
        # Log the promotion
        with open(LOG_PATH, "a") as log_file:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_file.write(
                f"[{timestamp}] Promoted '{ADMIN_USER['username']}' to admin role\n"
            )
        return True
    else:
        print("❌ Failed to promote user to admin role")
        print(f"Output: {output}")
        return False


def get_admin_token():
    """Log in as admin and get the access token"""
    print("\n--- Getting admin access token ---")
    try:
        response = requests.post(
            f"{API_BASE_URL}/api/auth/login",
            json={
                "username": ADMIN_USER["username"],
                "password": ADMIN_USER["password"],
            },
        )

        if response.status_code == 200:
            data = response.json()
            # Try both access patterns to handle different API response formats
            token = data.get("accessToken")
            if not token:
                # Try nested format
                token = data.get("token", {}).get("accessToken")

            # If still no token, check for other formats based on API response
            if not token and isinstance(data, dict):
                # Print response structure for debugging
                print(f"Response structure: {json.dumps(data, indent=2)}")

                # Try to find any key that might contain the token
                for key, value in data.items():
                    if isinstance(value, str) and len(value) > 40:  # Likely a JWT token
                        token = value
                        print(f"Found potential token in field: {key}")
                        break

            if token:
                print("✅ Admin access token obtained")
                # Log successful login
                with open(LOG_PATH, "a") as log_file:
                    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    log_file.write(
                        f"[{timestamp}] Admin '{ADMIN_USER['username']}' logged in successfully\n"
                    )
                return token
            else:
                print("❌ Access token not found in response")
                print(f"Response data: {data}")
        else:
            print(f"❌ Failed to log in as admin: {response.text}")
    except requests.RequestException as e:
        print(f"❌ Request error: {e}")
    except Exception as e:
        print(f"❌ Unexpected error: {e}")

    return None


def create_user(user_data, token, role_name):
    """Create a new user as admin"""
    try:
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

        # Admin users create users through the admin API
        response = requests.post(
            f"{API_BASE_URL}/api/admin/users",
            headers=headers,
            json={
                "username": user_data["username"],
                "email": user_data["email"],
                "password": user_data["password"],
                "role": user_data["role"],
                "skipVerification": True,  # Skip email verification for demo
            },
        )

        if response.status_code == 201:
            data = response.json()
            user_id = data.get("userId")
            print(f"✅ {role_name} created: {user_data['username']} (ID: {user_id})")
            # Log the user creation
            log_user_creation(
                role_name,
                user_data["username"],
                user_data["email"],
                user_data["password"],
                user_id,
            )
            return user_id
        else:
            print(
                f"❌ Failed to create {role_name} {user_data['username']}: {response.text}"
            )
            return None
    except requests.RequestException as e:
        print(f"❌ Request error: {e}")
        return None


def main():
    # Create log file header if it doesn't exist or is empty
    if not os.path.exists(LOG_PATH) or os.path.getsize(LOG_PATH) == 0:
        with open(LOG_PATH, "w") as log_file:
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            log_file.write(f"# User Creation Log - Started {timestamp}\n")
            log_file.write(
                "# Format: [timestamp] Created user_type: username='xxx', email='xxx', password='xxx'\n\n"
            )

    # Check if API server is running
    if not check_api_health():
        sys.exit(1)

    # Create admin user
    user_id = create_admin_user()
    if not user_id:
        sys.exit(1)

    # Promote user to admin role in MongoDB
    if not promote_to_admin():
        sys.exit(1)

    # Get admin access token
    admin_token = get_admin_token()
    if not admin_token:
        sys.exit(1)

    # Create supervisor users
    print("\n--- Creating supervisor users ---")
    for supervisor in SUPERVISOR_USERS:
        create_user(supervisor, admin_token, "Supervisor")

    # Create regular users
    print("\n--- Creating regular users ---")
    for user in REGULAR_USERS:
        create_user(user, admin_token, "Regular user")

    print("\n✨ User setup completed successfully!")
    print(f"\nCredential log saved to: {LOG_PATH}")
    print("\nCreated accounts:")
    print(f"- Admin: {ADMIN_USER['username']} / {ADMIN_USER['password']}")
    for supervisor in SUPERVISOR_USERS:
        print(f"- Supervisor: {supervisor['username']} / {supervisor['password']}")
    for user in REGULAR_USERS:
        print(f"- User: {user['username']} / {user['password']}")


if __name__ == "__main__":
    main()
