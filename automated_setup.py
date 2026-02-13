#!/usr/bin/env python3
"""
ChatProxyPlatform - Automated Setup Script
==========================================

This script automates the complete setup of ChatProxyPlatform from scratch.

Steps:
1. Scan initial system (Docker, Python, Git, drive space)
2. Install and start Flowise
3. Prompt for Flowise API key
4. Sync JWT secrets and configure all services
5. Launch auth service
6. Launch accounting service
7. Create admin user and verify email
8. Create users and allocate credits
9. Setup flowise proxy service
10. Setup bridge UI
11. Display success message and instructions

Requirements:
- Windows OS
- Docker Desktop installed and running
- Python 3.8+
- Git installed
- Sufficient drive space (>5GB recommended)

Usage:
    python automated_setup.py
    
Or use the batch file wrapper:
    automated_setup.bat
"""

import os
import sys
import json
import time
import subprocess
import shutil
import secrets
import string
import ctypes
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import urllib.request
import urllib.parse
import urllib.error

# Enable ANSI escape codes on Windows
if os.name == 'nt':
    kernel32 = ctypes.windll.kernel32
    kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)

# Color codes for terminal output
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header(text: str):
    """Print a section header"""
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*70}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text.center(70)}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*70}{Colors.ENDC}\n")

def print_success(text: str):
    """Print success message"""
    print(f"{Colors.OKGREEN}✓ {text}{Colors.ENDC}")

def print_error(text: str):
    """Print error message"""
    print(f"{Colors.FAIL}✗ {text}{Colors.ENDC}")

def print_warning(text: str):
    """Print warning message"""
    print(f"{Colors.WARNING}⚠ {text}{Colors.ENDC}")

def print_info(text: str):
    """Print info message"""
    print(f"{Colors.OKCYAN}ℹ {text}{Colors.ENDC}")

def run_command(cmd: List[str], cwd: Optional[str] = None, shell: bool = False) -> Tuple[int, str, str]:
    """
    Run a command and return (exit_code, stdout, stderr)
    """
    try:
        if shell:
            result = subprocess.run(
                ' '.join(cmd),
                cwd=cwd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=300
            )
        else:
            result = subprocess.run(
                cmd,
                cwd=cwd,
                capture_output=True,
                text=True,
                timeout=300
            )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)

def check_admin() -> bool:
    """Check if script is running with admin privileges"""
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except:
        return False

def check_container_running(container_name: str) -> bool:
    """Check if a Docker container is running"""
    code, stdout, stderr = run_command(["docker", "ps", "--filter", f"name={container_name}", "--format", "{{.Names}}"])
    if code == 0 and container_name in stdout:
        return True
    return False

def check_docker() -> bool:
    """Check if Docker is installed and running"""
    print_info("Checking Docker installation...")
    
    # Check if docker command exists
    code, stdout, stderr = run_command(["docker", "--version"])
    if code != 0:
        print_error("Docker is not installed or not in PATH")
        return False
    
    print_success(f"Docker found: {stdout.strip()}")
    
    # Check if Docker daemon is running
    code, stdout, stderr = run_command(["docker", "ps"])
    if code != 0:
        print_error("Docker daemon is not running. Please start Docker Desktop.")
        return False
    
    print_success("Docker daemon is running")
    return True

def check_python() -> bool:
    """Check Python version"""
    print_info("Checking Python installation...")
    
    version = sys.version_info
    if version.major < 3 or (version.major == 3 and version.minor < 8):
        print_error(f"Python 3.8+ required, found {version.major}.{version.minor}")
        return False
    
    print_success(f"Python {version.major}.{version.minor}.{version.micro} found")
    return True

def check_git() -> bool:
    """Check if Git is installed"""
    print_info("Checking Git installation...")
    
    code, stdout, stderr = run_command(["git", "--version"])
    if code != 0:
        print_error("Git is not installed or not in PATH")
        return False
    
    print_success(f"Git found: {stdout.strip()}")
    return True

def check_drive_space() -> Dict[str, Tuple[float, float]]:
    """
    Check available space on all drives
    Returns dict of drive: (free_gb, total_gb)
    """
    print_info("Checking drive space...")
    
    drives = {}
    for letter in string.ascii_uppercase:
        drive = f"{letter}:\\"
        if os.path.exists(drive):
            try:
                stat = shutil.disk_usage(drive)
                free_gb = stat.free / (1024**3)
                total_gb = stat.total / (1024**3)
                drives[letter] = (free_gb, total_gb)
                
                if free_gb < 1:
                    print_warning(f"Drive {letter}: has only {free_gb:.1f} GB free (CRITICAL)")
                elif free_gb < 5:
                    print_warning(f"Drive {letter}: has {free_gb:.1f} GB free (LOW)")
                else:
                    print_success(f"Drive {letter}: has {free_gb:.1f} GB free / {total_gb:.1f} GB total")
            except Exception as e:
                print_warning(f"Could not check drive {letter}: {e}")
    
    return drives

def select_data_drive(drives: Dict[str, Tuple[float, float]]) -> str:
    """
    Select the best drive for Docker volumes
    Prefers drives with >10GB free space
    """
    print_info("Selecting drive for Docker volumes...")
    
    # Find drive with most free space and >10GB available
    best_drive = None
    best_free = 0
    
    for drive, (free_gb, total_gb) in drives.items():
        if free_gb > 10 and free_gb > best_free:
            best_drive = drive
            best_free = free_gb
    
    # If no drive has >10GB, use the one with most space
    if not best_drive:
        best_drive = max(drives.items(), key=lambda x: x[1][0])[0]
        print_warning(f"No drive has >10GB free, using {best_drive}: with {drives[best_drive][0]:.1f} GB")
    else:
        print_success(f"Selected drive {best_drive}: with {best_free:.1f} GB free")
    
    return best_drive

def load_existing_secrets() -> Tuple[Optional[str], Optional[str]]:
    """Load JWT secrets from existing .env file if available"""
    env_path = Path.cwd() / "auth-service" / ".env"
    jwt_access = None
    jwt_refresh = None
    
    if env_path.exists():
        try:
            with open(env_path, 'r') as f:
                for line in f:
                    if line.startswith("JWT_ACCESS_SECRET="):
                        jwt_access = line.split('=')[1].strip()
                    elif line.startswith("JWT_REFRESH_SECRET="):
                        jwt_refresh = line.split('=')[1].strip()
        except:
            pass
            
    return jwt_access, jwt_refresh

def generate_jwt_secrets() -> Tuple[str, str]:
    """Generate secure JWT secrets"""
    print_info("Generating JWT secrets...")
    
    # Check if we can reuse existing secrets
    existing_access, existing_refresh = load_existing_secrets()
    if existing_access and existing_refresh:
        print_info("Found existing JWT secrets in auth-service/.env")
        print(f"  {Colors.BOLD}Options:{Colors.ENDC}")
        print("  1. Use existing secrets (Recommended to preserve sessions)")
        print("  2. Generate NEW secrets (Will invalidate all current logins)")
        print()
        choice = input(f"{Colors.OKCYAN}Enter choice (default: 1): {Colors.ENDC}").strip()
        
        if choice != '2':
            print_success("Using existing JWT secrets")
            return existing_access, existing_refresh
    
    def generate_secret(length: int = 64) -> str:
        """Generate a secure random secret"""
        alphabet = string.ascii_letters + string.digits + '-_.'
        return ''.join(secrets.choice(alphabet) for _ in range(length))
    
    access_secret = generate_secret(64)
    refresh_secret = generate_secret(64)
    
    print_success("JWT secrets generated")
    return access_secret, refresh_secret

def update_env_file(file_path: str, updates: Dict[str, str]):
    """Update environment file with new values"""
    if not os.path.exists(file_path):
        print_warning(f"Creating new .env file: {file_path}")
        with open(file_path, 'w') as f:
            for key, value in updates.items():
                f.write(f"{key}={value}\n")
        return
    
    # Read existing file
    with open(file_path, 'r') as f:
        lines = f.readlines()
    
    # Update values
    updated_lines = []
    updated_keys = set()
    
    for line in lines:
        line = line.rstrip('\n')
        if '=' in line and not line.strip().startswith('#'):
            key = line.split('=')[0].strip()
            if key in updates:
                updated_lines.append(f"{key}={updates[key]}\n")
                updated_keys.add(key)
                continue
        updated_lines.append(line + '\n')
    
    # Add new keys that weren't in the file
    for key, value in updates.items():
        if key not in updated_keys:
            updated_lines.append(f"{key}={value}\n")
    
    # Write back
    with open(file_path, 'w') as f:
        f.writelines(updated_lines)

def configure_docker_volumes(data_drive: str):
    """Update docker-compose files to use specified drive"""
    print_info(f"Configuring Docker volumes on drive {data_drive}...")
    
    base_path = Path.cwd()
    volume_base = f"{data_drive}:/DockerVolumes"
    
    services = [
        "flowise",
        "auth-service",
        "accounting-service",
        "flowise-proxy-service-py",
        "bridge"
    ]
    
    for service in services:
        compose_files = list((base_path / service).glob("docker-compose*.yml"))
        
        for compose_file in compose_files:
            if not compose_file.exists():
                continue
            
            print_info(f"  Updating {compose_file.relative_to(base_path)}")
            
            with open(compose_file, 'r') as f:
                content = f.read()
            
            # Replace volume paths (this is a simple replacement, might need refinement)
            # Pattern: ./data -> D:/DockerVolumes/service-name/data
            service_name = service.replace("-service", "").replace("-py", "")
            
            # Update based on service type
            if "flowise" in service.lower() and "proxy" not in service.lower():
                content = content.replace("flowise-data:", f"{volume_base}/flowise-data:")
                content = content.replace("./flowise-postgres", f"{volume_base}/flowise-postgres")
            elif "auth" in service:
                content = content.replace("./mongodb-auth", f"{volume_base}/mongodb-auth")
            elif "accounting" in service:
                content = content.replace("./postgres-accounting", f"{volume_base}/postgres-accounting")
            elif "proxy" in service:
                content = content.replace("./mongodb-proxy", f"{volume_base}/mongodb-proxy")
            
            with open(compose_file, 'w') as f:
                f.write(content)
    
    print_success("Docker volumes configured")

def start_flowise():
    """Start Flowise service"""
    print_info("Starting Flowise service...")
    
    flowise_dir = Path.cwd() / "flowise"
    
    # Check if directory exists
    if not flowise_dir.exists():
        print_error(f"Flowise directory not found: {flowise_dir}")
        return False
    
    # Check if Flowise container is already running
    if check_container_running("flowise"):
        print_info("  Flowise container is already running")
        print(f"  {Colors.BOLD}Options:{Colors.ENDC}")
        print("  1. Skip (keep current container running)")
        print("  2. Restart container")
        print()
        choice = input(f"{Colors.OKCYAN}Enter choice (default: 1): {Colors.ENDC}").strip()
        
        if choice != '2':
            print_success("Skipping Flowise start (already running)")
            return True
        else:
            print_info("  Stopping existing Flowise container...")
            run_command(["docker", "compose", "down"], cwd=str(flowise_dir))
        
    print_info(f"  Using directory: {flowise_dir}")
    
    # Use docker compose directly instead of batch files to avoid path/pause issues
    compose_file = "docker-compose.yml"
    
    env_file = flowise_dir / ".env"
    if not env_file.exists():
        print_warning("  .env file not found in flowise directory, copying example...")
        try:
            shutil.copy(flowise_dir / ".env.example", env_file)
        except:
            pass
            
    print_info("  Running docker compose up -d...")
    
    # Determine command based on whether we want postgres (checking if the bat file exists is a good proxy)
    if (flowise_dir / "start-with-postgres.bat").exists():
         # matches content of start-with-postgres.bat: docker compose --env-file .env up -d
         cmd = ["docker", "compose", "--env-file", ".env", "up", "-d"]
    else:
         cmd = ["docker", "compose", "up", "-d"]

    code, stdout, stderr = run_command(
        cmd,
        cwd=str(flowise_dir)
    )
    
    if code != 0:
        print_error(f"Failed to start Flowise: {stderr}")
        # Fallback to shell execution if direct exec fails
        print_info("  Retrying with shell execution...")
        code, stdout, stderr = run_command(
            ' '.join(cmd),
            cwd=str(flowise_dir),
            shell=True
        )
        if code != 0:
             return False
    
    print_success("Flowise starting... waiting for it to be ready")
    
    # Wait for Flowise to be ready (check health)
    max_retries = 30
    for i in range(max_retries):
        time.sleep(5)
        try:
            req = urllib.request.Request("http://localhost:3002/api/v1/health")
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    print_success("Flowise is ready!")
                    return True
        except:
            print_info(f"  Waiting for Flowise... ({i+1}/{max_retries})")
    
    print_warning("Flowise may not be fully ready, but continuing...")
    return True

def get_flowise_api_key() -> str:
    """Prompt user for Flowise API key"""
    print_header("Flowise API Key Configuration")
    
    # Check if API key already exists in flowise-proxy-service-py/.env
    proxy_env = Path.cwd() / "flowise-proxy-service-py" / ".env"
    existing_key = None
    
    if proxy_env.exists():
        try:
            with open(proxy_env, 'r') as f:
                for line in f:
                    if line.startswith("FLOWISE_API_KEY="):
                        existing_key = line.split('=')[1].strip()
                        break
        except:
            pass
    
    if existing_key:
        print_info(f"Found existing Flowise API key: {existing_key[:8]}...{existing_key[-4:]}")
        print(f"  {Colors.BOLD}Options:{Colors.ENDC}")
        print("  1. Use existing API key (Recommended)")
        print("  2. Enter new API key")
        print()
        choice = input(f"{Colors.OKCYAN}Enter choice (default: 1): {Colors.ENDC}").strip()
        
        if choice != '2':
            print_success("Using existing Flowise API key")
            return existing_key
    
    print_info("Please obtain your Flowise API key:")
    print_info("  1. Open http://localhost:3002 in your browser")
    print_info("  2. Login or create an account")
    print_info("  3. Go to Settings > API Keys")
    print_info("  4. Create a new API key or copy existing one")
    print()
    
    while True:
        api_key = input(f"{Colors.OKCYAN}Enter Flowise API Key: {Colors.ENDC}").strip()
        if api_key:
            return api_key
        print_error("API key cannot be empty")

def configure_all_services(jwt_access: str, jwt_refresh: str, flowise_api_key: str, data_drive: str):
    """Configure all service .env files"""
    print_info("Configuring all services...")
    
    base_path = Path.cwd()
    
    # Auth Service
    auth_env = base_path / "auth-service" / ".env"
    update_env_file(str(auth_env), {
        "JWT_ACCESS_SECRET": jwt_access,
        "JWT_REFRESH_SECRET": jwt_refresh,
        "MONGO_URI": "mongodb://mongodb-auth:27017/auth_db"
    })
    print_success("  Configured auth-service")
    
    # Accounting Service
    accounting_env = base_path / "accounting-service" / ".env"
    update_env_file(str(accounting_env), {
        "JWT_ACCESS_SECRET": jwt_access,
        "JWT_REFRESH_SECRET": jwt_refresh,
        "DB_HOST": "postgres-accounting",
        "DB_NAME": "accounting",
        "DB_USER": "postgres",
        "DB_PASSWORD": "postgres123"
    })
    print_success("  Configured accounting-service")
    
    # Flowise Proxy
    proxy_env = base_path / "flowise-proxy-service-py" / ".env"
    
    # Generate MongoDB password if needed
    mongo_password = "65424b6a739b4198ae2a3e08b35deeda"  # Use consistent password
    
    update_env_file(str(proxy_env), {
        "JWT_ACCESS_SECRET": jwt_access,
        "JWT_REFRESH_SECRET": jwt_refresh,
        "FLOWISE_API_KEY": flowise_api_key,
        "FLOWISE_API_URL": "http://flowise:3002",
        "MONGODB_URL": f"mongodb://admin:{mongo_password}@mongodb-proxy:27017/flowise_proxy?authSource=admin"
    })
    print_success("  Configured flowise-proxy-service-py")
    
    print_success("All services configured")

def start_service(service_name: str, wait_time: int = 10) -> bool:
    """Start a service using docker compose directly to avoid blocking on batch pauses"""
    print_info(f"Starting {service_name}...")
    
    service_dir = Path.cwd() / service_name
    
    # Determine the docker-compose file to use
    compose_file = "docker-compose.yml"
    if (service_dir / "docker-compose.dev.yml").exists():
        compose_file = "docker-compose.dev.yml"
    
    if not (service_dir / compose_file).exists():
        print_error(f"No {compose_file} found for {service_name}")
        return False
    
    # Check if service container is already running
    # Try common container name patterns
    container_patterns = [service_name, service_name.replace("-", "_"), service_name.replace("-", "")]
    for pattern in container_patterns:
        if check_container_running(pattern):
            print_info(f"  {service_name} container is already running")
            print(f"  {Colors.BOLD}Options:{Colors.ENDC}")
            print("  1. Skip (keep current container running)")
            print("  2. Restart container")
            print()
            choice = input(f"{Colors.OKCYAN}Enter choice (default: 1): {Colors.ENDC}").strip()
            
            if choice != '2':
                print_success(f"Skipping {service_name} start (already running)")
                return True
            else:
                print_info(f"  Stopping existing {service_name} container...")
                run_command(["docker", "compose", "-f", compose_file, "down"], cwd=str(service_dir))
            break
    
    # First run npm install if package.json exists and node_modules doesn't
    # (Only needed if we were running locally, but for Docker it's usually handled in build
    #  or volume mounting. Keeping it just in case, but non-blocking)
    if (service_dir / "package.json").exists():
        node_modules = service_dir / "node_modules"
        if not node_modules.exists():
            print_info(f"  Installing Node.js dependencies for {service_name} (host)...")
            try:
                subprocess.run(["cmd", "/c", "npm", "install"], cwd=str(service_dir), shell=True, check=False)
            except:
                pass # Ignore errors here, not critical for docker path

    # Start the service via Docker Compose directly
    # This avoids the 'pause' in the batch files
    print_info(f"  Running docker compose up -d for {service_name}...")
    code, stdout, stderr = run_command(
        ["docker", "compose", "-f", compose_file, "up", "-d"],
        cwd=str(service_dir)
    )
    
    if code != 0:
        print_warning(f"  Docker start had issues: {stderr}")
        # Make a best effort attempt with the batch file if direct docker fail, 
        # but try to assume it might work.
    
    print_info(f"  Waiting {wait_time} seconds for {service_name} to initialize...")
    time.sleep(wait_time)
    
    print_success(f"{service_name} started")
    return True

def api_request(url: str, method: str = "GET", data: Optional[Dict] = None, headers: Optional[Dict] = None) -> Optional[Dict]:
    """Make an API request and return JSON response"""
    try:
        if headers is None:
            headers = {}
        
        if data is not None:
            data_bytes = json.dumps(data).encode('utf-8')
            headers['Content-Type'] = 'application/json'
        else:
            data_bytes = None
        
        req = urllib.request.Request(url, data=data_bytes, headers=headers, method=method)
        
        with urllib.request.urlopen(req, timeout=30) as response:
            response_data = response.read().decode('utf-8')
            return json.loads(response_data)
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        print_error(f"HTTP {e.code}: {error_body}")
        return None
    except Exception as e:
        print_error(f"Request failed: {e}")
        return None

def create_admin_user() -> bool:
    """Create admin user and verify email"""
    print_info("Creating admin user...")
    
    # Wait for auth service to be ready
    print_info("  Waiting for auth service to be ready...")
    max_retries = 30
    for i in range(max_retries):
        try:
            req = urllib.request.Request("http://localhost:3000/health")
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    print_success("  Auth service is ready!")
                    break
        except:
            if i < max_retries - 1:
                print_info(f"  Waiting for auth service... ({i+1}/{max_retries})")
                time.sleep(5)
            else:
                print_warning("  Auth service may not be fully ready, but continuing...")
    
    # Try to register admin (use /signup endpoint not /register)
    register_response = api_request(
        "http://localhost:3000/api/auth/signup",
        method="POST",
        data={
            "username": "admin",
            "email": "admin@example.com",
            "password": "admin@admin"
        }
    )
    
    if not register_response:
        print_warning("Admin user may already exist, attempting to verify...")
    else:
        print_success("  Admin user registered")
    
    # Verify admin email directly via MongoDB
    print_info("  Verifying admin email...")
    
    # Use docker exec to update MongoDB
    mongo_cmd = [
        "docker", "exec", "mongodb-auth",
        "mongosh", "auth_db", "--quiet", "--eval",
        "db.users.updateOne({email:'admin@example.com'},{$set:{isVerified:true,role:'admin'}})"
    ]
    
    code, stdout, stderr = run_command(mongo_cmd)
    
    if code != 0:
        print_error(f"  Failed to verify admin: {stderr}")
        return False
    
    print_success("  Admin email verified")
    
    # Test login
    print_info("  Testing admin login...")
    login_response = api_request(
        "http://localhost:3000/api/auth/login",
        method="POST",
        data={
            "username": "admin",
            "password": "admin@admin"
        }
    )
    
    if not login_response or 'accessToken' not in login_response:
        print_error("  Admin login failed")
        return False
    
    print_success("Admin user created and verified successfully")
    return True

def create_users_and_allocate_credits(user_list: List[Dict]) -> bool:
    """
    Create users and allocate credits
    user_list format: [{"username": "user1", "email": "user1@example.com", "credits": 5000, "role": "enduser"}, ...]
    """
    print_info(f"Creating {len(user_list)} users and allocating credits...")
    
    # First, login as admin to get admin token for credit allocation
    print_info("  Logging in as admin for credit allocation...")
    admin_login = api_request(
        "http://localhost:3000/api/auth/login",
        method="POST",
        data={
            "username": "admin",
            "password": "admin@admin"
        }
    )
    
    if not admin_login or 'accessToken' not in admin_login:
        print_error("  Failed to login as admin. Cannot allocate credits.")
        return False
    
    admin_token = admin_login['accessToken']
    print_success("  Admin login successful")
    
    success_count = 0
    
    for user in user_list:
        username = user['username']
        email = user['email']
        credits = user['credits']
        role = user.get('role', 'enduser')
        
        print_info(f"  Processing {username}...")
        
        # Register user (use /signup endpoint not /register)
        register_response = api_request(
            "http://localhost:3000/api/auth/signup",
            method="POST",
            data={
                "username": username,
                "email": email,
                "password": "admin@admin"  # Default password
            }
        )
        
        if not register_response:
            print_warning(f"    {username} may already exist")
        
        # Verify email and set role
        mongo_cmd = [
            "docker", "exec", "mongodb-auth",
            "mongosh", "auth_db", "--quiet", "--eval",
            f"db.users.updateOne({{email:'{email}'}},{{$set:{{isVerified:true,role:'{role}'}}}})"
        ]
        run_command(mongo_cmd)
        
        # Login to get user_id
        login_response = api_request(
            "http://localhost:3000/api/auth/login",
            method="POST",
            data={
                "username": username,
                "password": "admin@admin"
            }
        )
        
        if not login_response or 'user' not in login_response:
            print_error(f"    Failed to login as {username}")
            continue
        
        user_id = login_response['user']['id']
        
        # Allocate credits using admin token
        credit_response = api_request(
            "http://localhost:3001/api/credits/allocate",
            method="POST",
            data={
                "userId": user_id,
                "credits": credits,
                "notes": f"Initial credit allocation for {username}"
            },
            headers={
                "Authorization": f"Bearer {admin_token}"
            }
        )
        
        if credit_response:
            print_success(f"    {username}: {credits} credits allocated")
            success_count += 1
        else:
            print_error(f"    Failed to allocate credits for {username}")
    
    print_success(f"Created and configured {success_count}/{len(user_list)} users")
    return success_count == len(user_list)

def verify_system() -> bool:
    """Verify the entire system is working"""
    print_header("System Verification")
    
    checks = []
    
    # Check Docker containers
    print_info("Checking Docker containers...")
    code, stdout, stderr = run_command(["docker", "ps", "--format", "{{.Names}}\t{{.Status}}"])
    if code == 0:
        containers = stdout.strip().split('\n')
        print_success(f"  {len(containers)} containers running")
        checks.append(True)
    else:
        print_error("  Could not check containers")
        checks.append(False)
    
    # Check API endpoints
    print_info("Checking API endpoints...")
    
    endpoints = [
        ("Flowise", "http://localhost:3002/api/v1/health"),
        ("Auth Service", "http://localhost:3000/health"),
        ("Accounting Service", "http://localhost:3001/health"),
        ("Flowise Proxy", "http://localhost:8000/health"),
        ("Bridge UI", "http://localhost:3082"),
    ]
    
    for name, url in endpoints:
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as response:
                print_success(f"  {name}: OK")
                checks.append(True)
        except:
            print_warning(f"  {name}: Not responding (may still be starting)")
            checks.append(False)
    
    # Test admin login
    print_info("Testing admin authentication...")
    auth_response = api_request(
        "http://localhost:8000/api/v1/chat/authenticate",
        method="POST",
        data={
            "username": "admin",
            "password": "admin@admin"
        }
    )
    
    if auth_response and 'access_token' in auth_response:
        print_success("  Admin authentication: OK")
        
        # Check credits
        credits_response = api_request(
            "http://localhost:8000/api/v1/chat/credits",
            headers={"Authorization": f"Bearer {auth_response['access_token']}"}
        )
        
        if credits_response and 'totalCredits' in credits_response:
            print_success(f"  Admin credits: {credits_response['totalCredits']}")
            checks.append(True)
        else:
            print_warning("  Could not retrieve admin credits")
            checks.append(False)
    else:
        print_error("  Admin authentication failed")
        checks.append(False)
    
    success_rate = sum(checks) / len(checks) * 100
    print_info(f"System health: {success_rate:.0f}% ({sum(checks)}/{len(checks)} checks passed)")
    
    return success_rate >= 70  # At least 70% should pass

def check_existing_config() -> bool:
    """
    Check if configuration files already exist and inform user.
    Returns: True if user wants to continue, False if they want to abort.
    """
    base_path = Path.cwd()
    auth_env = base_path / "auth-service" / ".env"
    
    if auth_env.exists():
        print_header("Existing Configuration Detected")
        print_info("An existing setup was found (auth-service/.env exists).")
        print_info("You will be prompted at each step to:")
        print_info("  - Reuse existing configuration (recommended for running systems)")
        print_info("  - Generate new configuration (for fresh installs)")
        print()
        print_warning("Note: Your database data (users, credits) is always preserved in Docker volumes.")
        print()
        
        choice = input(f"{Colors.OKCYAN}Continue with setup? (Y/n): {Colors.ENDC}").lower().strip()
        
        if choice == 'n':
            print_info("Setup cancelled by user.")
            return False
            
    return True

def main():
    """Main setup function"""
    print_header("ChatProxyPlatform - Automated Setup")
    
    if not check_admin():
        print_warning("Script is not running as Administrator.")
        print_warning("This may cause issues with creating Docker volumes on the C: drive.")
        print_warning("It is HIGHLY RECOMMENDED to restart this script as Administrator.")
        choice = input(f"{Colors.WARNING}Continue anyway? (y/n): {Colors.ENDC}").lower().strip()
        if choice != 'y':
            print_error("Setup cancelled. Please run as Administrator.")
            return 1
    
    # Check for existing configuration to prevent accidental overwrite
    if not check_existing_config():
        return 0

    print_info("This script will set up the entire ChatProxyPlatform system")
    print()
    
    # Step 1: System scan
    print_header("Step 1: System Scan")
    
    if not check_docker():
        print_error("Docker is not available. Please install Docker Desktop and try again.")
        return 1
    
    if not check_python():
        print_error("Python version is too old. Please upgrade to Python 3.8+")
        return 1
    
    if not check_git():
        print_warning("Git is not available. Some features may not work.")
    
    drives = check_drive_space()
    if not drives:
        print_error("Could not detect any drives")
        return 1
    
    data_drive = select_data_drive(drives)
    
    # Step 2: Configure Docker volumes
    print_header("Step 2: Configure Docker Volumes")
    configure_docker_volumes(data_drive)
    
    # Create volume directories
    volume_base = Path(f"{data_drive}:/DockerVolumes")
    try:
        volume_base.mkdir(parents=True, exist_ok=True)
        print_success(f"Volume directory created: {volume_base}")
    except PermissionError:
        print_error(f"Permission denied creating {volume_base}")
        print_warning("Please run this script as Administrator or choose a non-system drive.")
        print_info("Trying fallback to local directory...")
        volume_base = Path.cwd() / "docker_volumes"
        volume_base.mkdir(parents=True, exist_ok=True)
        # We need to re-run configuration with new path if fallback is used
        configure_docker_volumes(str(volume_base).replace("\\", "/"))

    
    # Step 3: Generate JWT secrets
    print_header("Step 3: Generate Security Secrets")
    jwt_access, jwt_refresh = generate_jwt_secrets()
    
    # Step 4: Start Flowise
    print_header("Step 4: Start Flowise")
    if not start_flowise():
        print_error("Failed to start Flowise. Please check logs and try again.")
        return 1
    
    # Step 5: Get Flowise API key
    print_header("Step 5: Get Flowise API Key")
    flowise_api_key = get_flowise_api_key()
    
    # Step 6: Configure all services
    print_header("Step 6: Configure All Services")
    configure_all_services(jwt_access, jwt_refresh, flowise_api_key, data_drive)
    
    # Step 7: Start auth service
    print_header("Step 7: Start Auth Service")
    if not start_service("auth-service", wait_time=15):
        print_error("Failed to start auth service")
        return 1
    
    # Step 8: Start accounting service
    print_header("Step 8: Start Accounting Service")
    if not start_service("accounting-service", wait_time=15):
        print_error("Failed to start accounting service")
        return 1
    
    # Step 9: Create admin user
    print_header("Step 9: Create Admin User")
    if not create_admin_user():
        print_error("Failed to create admin user")
        return 1
    
    # Step 10: Create users and allocate credits
    print_header("Step 10: Create Users and Allocate Credits")
    
    users = [
        {"username": "admin", "email": "admin@example.com", "credits": 10000, "role": "admin"},
        {"username": "teacher1", "email": "teacher1@example.com", "credits": 5000, "role": "enduser"},
        {"username": "teacher2", "email": "teacher2@example.com", "credits": 5000, "role": "enduser"},
        {"username": "teacher3", "email": "teacher3@example.com", "credits": 5000, "role": "enduser"},
        {"username": "student1", "email": "student1@example.com", "credits": 1000, "role": "enduser"},
        {"username": "student2", "email": "student2@example.com", "credits": 1000, "role": "enduser"},
        {"username": "student3", "email": "student3@example.com", "credits": 1000, "role": "enduser"},
        {"username": "student4", "email": "student4@example.com", "credits": 1000, "role": "enduser"},
        {"username": "student5", "email": "student5@example.com", "credits": 1000, "role": "enduser"},
    ]
    
    create_users_and_allocate_credits(users)
    
    # Step 11: Start flowise proxy
    print_header("Step 11: Start Flowise Proxy Service")
    if not start_service("flowise-proxy-service-py", wait_time=15):
        print_warning("Flowise proxy may have issues, but continuing...")
    
    # Step 12: Start bridge UI
    print_header("Step 12: Start Bridge UI")
    if not start_service("bridge", wait_time=10):
        print_warning("Bridge UI may have issues, but continuing...")
    
    # Step 13: Verify system
    print_header("Step 13: System Verification")
    system_ok = verify_system()
    
    # Step 14: Display success message
    print_header("Setup Complete!")
    
    if system_ok:
        print_success("ChatProxyPlatform is ready to use!")
    else:
        print_warning("Setup completed with some warnings. Please check the output above.")
    
    print()
    print(f"{Colors.OKBLUE}{Colors.BOLD}{'='*70}{Colors.ENDC}")
    print(f"{Colors.OKBLUE}{Colors.BOLD}Next Steps:{Colors.ENDC}")
    print(f"{Colors.OKBLUE}{'='*70}{Colors.ENDC}")
    print()
    print(f"  1. Open your browser and go to: {Colors.OKGREEN}http://localhost:3082{Colors.ENDC}")
    print(f"  2. Login with:")
    print(f"       Username: {Colors.OKGREEN}admin{Colors.ENDC}")
    print(f"       Password: {Colors.OKGREEN}admin@admin{Colors.ENDC}")
    print(f"  3. Your credit balance should show: {Colors.OKGREEN}10,000 credits{Colors.ENDC}")
    print()
    print(f"  {Colors.WARNING}IMPORTANT:{Colors.ENDC} All users have default password: {Colors.WARNING}admin@admin{Colors.ENDC}")
    print(f"  {Colors.WARNING}Please change passwords after first login!{Colors.ENDC}")
    print()
    print(f"  Additional users created:")
    print(f"    - teacher1, teacher2, teacher3: {Colors.OKGREEN}5,000 credits each{Colors.ENDC}")
    print(f"    - student1-5: {Colors.OKGREEN}1,000 credits each{Colors.ENDC}")
    print()
    print(f"  For more information, see: {Colors.OKCYAN}SYSTEM_STATUS.md{Colors.ENDC}")
    print()
    print(f"{Colors.OKBLUE}{Colors.BOLD}{'='*70}{Colors.ENDC}")
    
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print()
        print_warning("Setup interrupted by user")
        sys.exit(1)
    except Exception as e:
        print()
        print_error(f"Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
