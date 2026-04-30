#!/usr/bin/env python3
"""
BHSS-Aware User Management Script for Batch Account Creation
Supports both localhost (dev) and BHSS environment configuration.

Input priority:
  1. --csv <path>  (CSV file with columns: username,password[,role][,email])
  2. CSV_FILE env var
  3. Built-in default list (fallback / demo)
"""

import argparse
import csv
import json
import requests
import os
import datetime
import sys
from urllib.parse import quote
from typing import Dict, Optional, Any, List

LOG_FILE = "add_credits_bhss.log"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_PATH = os.path.join(SCRIPT_DIR, LOG_FILE)

# Configuration - Support environment override
def get_config():
    """Load configuration from environment or use defaults"""
    return {
        "API_BASE_URL": os.getenv("AUTH_SERVICE_URL", "http://localhost:3000"),
        "ACCOUNT_BASE_URL": os.getenv("ACCOUNT_SERVICE_URL", "http://localhost:3001"),
        "ENVIRONMENT": os.getenv("BATCH_ENV", "local"),
    }

CONFIG = get_config()
API_BASE_URL = CONFIG["API_BASE_URL"]
ACCOUNT_BASE_URL = CONFIG["ACCOUNT_BASE_URL"]

def log(message: str, level: str = "INFO"):
    """Log messages to file and stdout"""
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_entry = f"[{timestamp}] {level}: {message}"
    print(log_entry)
    with open(LOG_PATH, "a") as log_file:
        log_file.write(log_entry + "\n")

def validate_service_connectivity():
    """Validate that services are reachable before batch operation"""
    try:
        auth_response = requests.get(f"{API_BASE_URL}/health", timeout=5)
        if auth_response.status_code != 200:
            log(f"Auth service health check failed: {auth_response.status_code}", "ERROR")
            return False
    except requests.exceptions.RequestException as e:
        log(f"Cannot reach Auth service at {API_BASE_URL}: {e}", "ERROR")
        return False
    
    try:
        acc_response = requests.get(f"{ACCOUNT_BASE_URL}/health", timeout=5)
        if acc_response.status_code != 200:
            log(f"Accounting service health check failed: {acc_response.status_code}", "ERROR")
            return False
    except requests.exceptions.RequestException as e:
        log(f"Cannot reach Accounting service at {ACCOUNT_BASE_URL}: {e}", "ERROR")
        return False
    
    log("✅ Service connectivity validated", "SUCCESS")
    return True

def get_admin_token(username: str, password: str) -> Optional[str]:
    """Login as admin and get access token"""
    try:
        response = requests.post(
            f"{API_BASE_URL}/api/auth/login",
            json={"username": username, "password": password},
            timeout=10
        )
        
        if response.status_code == 200:
            data = response.json()
            token = data.get("accessToken") or data.get("token", {}).get("accessToken")
            if token:
                log(f"✅ Admin '{username}' logged in successfully", "SUCCESS")
                return token
    except requests.exceptions.RequestException as e:
        log(f"❌ Login failed for admin '{username}': {e}", "ERROR")
    
    return None

def create_user_account(admin_token: str, sub: str, email: str, role: str, username: str = None) -> tuple:
    """Create user account in accounting service"""
    create_user_url = f"{ACCOUNT_BASE_URL}/api/admin/users"
    
    headers = {
        "Authorization": f"Bearer {admin_token}",
        "Content-Type": "application/json",
    }
    
    payload = {"sub": sub, "email": email, "role": role}
    if username:
        payload["username"] = username
    
    try:
        response = requests.post(create_user_url, headers=headers, json=payload, timeout=10)
        return response.status_code, response.json() if response.text else {}
    except requests.exceptions.RequestException as e:
        return None, f"Request failed: {e}"

def allocate_credit_to_user(email: str, credits: int, admin_token: str) -> bool:
    """Allocate credits to user by email"""
    allocate_url = f"{ACCOUNT_BASE_URL}/api/credits/allocate-by-email"
    
    headers = {
        "Authorization": f"Bearer {admin_token}",
        "Content-Type": "application/json",
    }
    
    payload = {"email": email, "credits": credits}
    
    try:
        response = requests.post(allocate_url, headers=headers, json=payload, timeout=10)
        return response.status_code == 200
    except requests.exceptions.RequestException as e:
        log(f"❌ Credit allocation failed for {email}: {e}", "ERROR")
        return False

def batch_create_users(admin_token: str, users: List[Dict], skip_verification: bool = True) -> Dict:
    """Create multiple users via the auth-service batch endpoint."""
    batch_url = f"{API_BASE_URL}/api/admin/users/batch"
    headers = {
        "Authorization": f"Bearer {admin_token}",
        "Content-Type": "application/json",
    }
    payload = {"users": users, "skipVerification": skip_verification}
    try:
        response = requests.post(batch_url, headers=headers, json=payload, timeout=30)
        data = response.json() if response.text else {}
        if response.status_code == 201:
            return data
        log(f"❌ Batch create returned {response.status_code}: {data}", "ERROR")
        return {"error": data, "results": [], "summary": {"total": len(users), "successful": 0, "failed": len(users)}}
    except requests.exceptions.RequestException as e:
        log(f"❌ Batch create request failed: {e}", "ERROR")
        return {"error": str(e), "results": [], "summary": {"total": len(users), "successful": 0, "failed": len(users)}}


def load_users_from_csv(csv_path: str) -> List[Dict]:
    """Read username,password[,role][,email] CSV and return user dicts."""
    users = []
    with open(csv_path, newline='', encoding='utf-8') as fh:
        reader = csv.DictReader(fh)
        # Normalise header names to lowercase stripped
        fieldnames_lower = [f.strip().lower() for f in (reader.fieldnames or [])]
        for row in reader:
            # Re-key using normalised names
            norm = {k.strip().lower(): v.strip() for k, v in row.items()}
            username = norm.get('username', '').strip()
            password = norm.get('password', '').strip()
            if not username or not password:
                log(f"⚠️  Skipping row missing username or password: {norm}", "WARNING")
                continue
            user: Dict = {"username": username, "password": password}
            role = norm.get('role', '').strip()
            if role:
                user['role'] = role
            email = norm.get('email', '').strip()
            if email:
                user['email'] = email
            users.append(user)
    return users


def main():
    """Main batch user creation workflow"""
    parser = argparse.ArgumentParser(description="Batch create users via auth-service")
    parser.add_argument('--csv', dest='csv_file', default=None, help='Path to CSV file (username,password[,role][,email])')
    args = parser.parse_args()

    log(f"=== BHSS Batch User Creation (Environment: {CONFIG['ENVIRONMENT']}) ===")
    log(f"Auth Service: {API_BASE_URL}")
    log(f"Accounting Service: {ACCOUNT_BASE_URL}")

    # Validate connectivity
    if not validate_service_connectivity():
        log("❌ Service connectivity validation failed. Aborting batch operation.", "ERROR")
        sys.exit(1)

    admin_user = {
        "username": "admin",
        "password": os.getenv("ADMIN_PASSWORD", "admin@admin"),
    }

    # Resolve user list: CLI arg > env var > built-in fallback
    csv_path = args.csv_file or os.getenv("CSV_FILE")
    if csv_path:
        if not os.path.isfile(csv_path):
            log(f"❌ CSV file not found: {csv_path}", "ERROR")
            sys.exit(1)
        log(f"Loading users from CSV: {csv_path}")
        users_to_create = load_users_from_csv(csv_path)
        log(f"Loaded {len(users_to_create)} users from CSV")
    else:
        log("No CSV file provided — using built-in default list", "WARNING")
        users_to_create = [
            {"username": "batchuser1", "password": "Password1!", "role": "enduser"},
            {"username": "batchuser2", "password": "Password2!", "role": "enduser"},
        ]

    if not users_to_create:
        log("❌ No users to create. Aborting.", "ERROR")
        sys.exit(1)

    # Get admin token
    admin_token = get_admin_token(admin_user["username"], admin_user["password"])
    if not admin_token:
        log("❌ Failed to obtain admin token. Aborting batch operation.", "ERROR")
        sys.exit(1)

    # Create all users in a single batch request
    log(f"Submitting batch of {len(users_to_create)} users...")
    batch_result = batch_create_users(admin_token, users_to_create)

    summary = batch_result.get("summary", {})
    successful = summary.get("successful", 0)
    failed = summary.get("failed", 0)
    total = summary.get("total", len(users_to_create))

    # Log per-user results
    for r in batch_result.get("results", []):
        if r.get("success"):
            log(f"✅ Created: {r.get('username')} ({r.get('email', '')})", "SUCCESS")
            # Allocate credits to accounting service if needed
            email = r.get("email", f"{r.get('username')}@internal.local")
            if not allocate_credit_to_user(email, 1000, admin_token):
                log(f"⚠️  Credit allocation issue for {email}", "WARNING")
        else:
            log(f"❌ Failed: {r.get('username')} — {r.get('message', '')}", "ERROR")

    log(f"\n=== Summary ===\nSuccessful: {successful}\nFailed: {failed}\nTotal: {total}", "INFO")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
