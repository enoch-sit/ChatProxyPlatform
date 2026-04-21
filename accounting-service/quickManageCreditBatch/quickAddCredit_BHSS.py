#!/usr/bin/env python3
"""
BHSS-Aware User Management Script for Batch Account Creation
Supports both localhost (dev) and BHSS environment configuration
"""

import json
import requests
import os
import datetime
import sys
from urllib.parse import quote
from typing import Dict, Optional, Any

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

def main():
    """Main batch user creation workflow"""
    log(f"=== BHSS Batch User Creation (Environment: {CONFIG['ENVIRONMENT']}) ===")
    log(f"Auth Service: {API_BASE_URL}")
    log(f"Accounting Service: {ACCOUNT_BASE_URL}")
    
    # Validate connectivity
    if not validate_service_connectivity():
        log("❌ Service connectivity validation failed. Aborting batch operation.", "ERROR")
        sys.exit(1)
    
    # Example batch: this can be extended to read from CSV or CLI args
    admin_user = {
        "username": "admin",
        "password": os.getenv("ADMIN_PASSWORD", "admin@admin"),
    }
    
    users_to_create = [
        {"username": "batchuser1", "email": "batchuser1@bhss.edu.hk", "role": "enduser"},
        {"username": "batchuser2", "email": "batchuser2@bhss.edu.hk", "role": "enduser"},
    ]
    
    # Get admin token
    admin_token = get_admin_token(admin_user["username"], admin_user["password"])
    if not admin_token:
        log("❌ Failed to obtain admin token. Aborting batch operation.", "ERROR")
        sys.exit(1)
    
    # Create users batch
    successful = 0
    failed = 0
    
    for user_data in users_to_create:
        status_code, response = create_user_account(
            admin_token,
            user_data.get("username"),  # Using username as sub for now
            user_data["email"],
            user_data["role"],
            user_data.get("username")
        )
        
        if status_code in [201, 409]:  # 201 created, 409 conflict (already exists)
            log(f"✅ User created/exists: {user_data['email']}", "SUCCESS")
            if allocate_credit_to_user(user_data["email"], 1000, admin_token):
                log(f"✅ Credits allocated: {user_data['email']}", "SUCCESS")
                successful += 1
            else:
                log(f"⚠️ Credit allocation issue: {user_data['email']}", "WARNING")
        else:
            log(f"❌ Failed to create user {user_data['email']}: {status_code} - {response}", "ERROR")
            failed += 1
    
    log(f"\n=== Summary ===\nSuccessful: {successful}\nFailed: {failed}\nTotal: {len(users_to_create)}", "INFO")
    sys.exit(0 if failed == 0 else 1)

if __name__ == "__main__":
    main()
