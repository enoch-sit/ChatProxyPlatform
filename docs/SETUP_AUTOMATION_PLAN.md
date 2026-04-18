# Setup Automation Plan
**ChatProxyPlatform - From Zero to 10,000 Credits**

---

## 🎯 Objective

Automate the complete setup of ChatProxyPlatform on Windows systems, from fresh installation to having an admin user with 10,000 credits ready for testing, in under 15 minutes with a single command.

---

## 📊 Setup Journey

### Manual Process (Before Automation)
**Time Required**: 2-3 hours  
**Steps**: 40+ manual operations  
**Error Rate**: High (configuration mismatches common)

#### Step-by-Step Manual Process:
1. Check Docker Desktop installed and running
2. Check Python installed
3. Check Git installed
4. Manually check C: drive space
5. Discover D: drive exists with more space
6. Manually update 5 docker-compose.yml files
7. Create volume directories
8. Generate JWT secrets
9. Manually update auth-service .env
10. Manually update accounting-service .env
11. Manually update flowise-proxy .env
12. Start Flowise service
13. Wait for Flowise to initialize
14. Login to Flowise UI
15. Create API key
16. Copy API key to flowise-proxy .env
17. Start MongoDB (auth)
18. Wait for MongoDB initialization
19. Start auth service
20. Debug MongoDB connection issues
21. Fix auth-service .env MONGO_URI
22. Restart auth service
23. Start PostgreSQL (accounting)
24. Start accounting service
25. Debug JWT secret mismatches
26. Update JWT secrets
27. Restart accounting service
28. Register admin user
29. Get verification code from logs
30. Connect to MongoDB
31. Manually verify admin email
32. Debug emailVerified vs isVerified field
33. Test admin login
34. Get admin JWT token
35. Allocate credits to admin
36. Register teacher users (x3)
37. Verify teacher emails (x3)
38. Allocate credits to teachers (x3)
39. Register student users (x5)
40. Verify student emails (x5)
41. Allocate credits to students (x5)
42. Start flowise-proxy service
43. Debug MongoDB password mismatch
44. Fix flowise-proxy .env
45. Restart flowise-proxy
46. Start Bridge UI
47. Test login through UI
48. Verify credit balance displays

**Problems**:
- ❌ Easy to miss steps
- ❌ Configuration mismatches frequent
- ❌ Database connection issues common
- ❌ JWT secret synchronization manual
- ❌ No validation between steps
- ❌ Hard to reproduce
- ❌ Difficult for new users

---

### Automated Process (After Automation)
**Time Required**: 10-15 minutes  
**Steps**: 1 command + 1 user input (API key)  
**Error Rate**: Low (automated validation at each step)

#### Automated Flow:
```
automated_setup.bat
  ↓
1. System Scan (30 seconds)
   - Check Docker
   - Check Python
   - Check Git
   - Check all drives
   - Select optimal drive
  ↓
2. Configure Docker Volumes (10 seconds)
   - Update all docker-compose.yml
   - Create volume directories
  ↓
3. Generate Security Secrets (1 second)
   - JWT access secret
   - JWT refresh secret
  ↓
4. Start Flowise (2 minutes)
   - docker-compose up
   - Wait for health check
  ↓
5. Prompt for API Key (USER INPUT)
   - Display instructions
   - Wait for user to create key
   - Accept input
  ↓
6. Configure All Services (5 seconds)
   - Update auth-service .env
   - Update accounting-service .env
   - Update flowise-proxy .env
   - Synchronize JWT secrets
  ↓
7. Start Auth Service (1 minute)
   - npm install if needed
   - docker-compose up
   - Wait for health check
  ↓
8. Start Accounting Service (1 minute)
   - npm install if needed
   - docker-compose up
   - Wait for health check
  ↓
9. Create Admin User (30 seconds)
   - POST /api/auth/register
   - Verify email via MongoDB
   - Test login
   - Allocate 10,000 credits
  ↓
10. Create Additional Users (2 minutes)
    - Register 3 teachers
    - Verify emails
    - Allocate 5,000 credits each
    - Register 5 students
    - Verify emails
    - Allocate 1,000 credits each
  ↓
11. Start Flowise Proxy (1 minute)
    - docker-compose up
    - Wait for health check
  ↓
12. Start Bridge UI (1 minute)
    - npm install if needed
    - docker-compose up
    - Wait for health check
  ↓
13. System Verification (30 seconds)
    - Test all API endpoints
    - Test admin authentication
    - Verify credit balance
    - Display system health
  ↓
14. Success Message
    - Display access URL
    - Show login credentials
    - List all users
    - Show next steps
```

**Benefits**:
- ✅ Single command execution
- ✅ Automatic error detection
- ✅ Configuration synchronization guaranteed
- ✅ Progress feedback at each step
- ✅ Health checks and validation
- ✅ Reproducible across environments
- ✅ Beginner-friendly

---

## 🏗️ Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    automated_setup.bat                      │
│                    (Windows Launcher)                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    automated_setup.py                       │
│                  (Main Orchestrator)                        │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Step 1: System Scanner                             │   │
│  │  - check_docker()                                   │   │
│  │  - check_python()                                   │   │
│  │  - check_git()                                      │   │
│  │  - check_drive_space()                              │   │
│  │  - select_data_drive()                              │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Step 2: Volume Configurator                        │   │
│  │  - configure_docker_volumes()                       │   │
│  │  - update docker-compose files                      │   │
│  │  - create volume directories                        │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Step 3: Secret Generator                           │   │
│  │  - generate_jwt_secrets()                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Step 4: Service Orchestrator                       │   │
│  │  - start_flowise()                                  │   │
│  │  - start_service("auth-service")                    │   │
│  │  - start_service("accounting-service")              │   │
│  │  - start_service("flowise-proxy-service-py")        │   │
│  │  - start_service("bridge")                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Step 5: User Provisioner                           │   │
│  │  - create_admin_user()                              │   │
│  │  - create_users_and_allocate_credits()              │   │
│  │  - verify email via MongoDB                         │   │
│  │  - allocate credits via API                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Step 6: System Verifier                            │   │
│  │  - verify_system()                                  │   │
│  │  - test all endpoints                               │   │
│  │  - check authentication                             │   │
│  │  - verify credits                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Step 7: Success Reporter                           │   │
│  │  - Display system status                            │   │
│  │  - Show access URL                                  │   │
│  │  - List credentials                                 │   │
│  │  - Provide next steps                               │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   External Dependencies                     │
│  - Docker Desktop (containers)                              │
│  - MongoDB (auth, proxy databases)                          │
│  - PostgreSQL (accounting, flowise databases)               │
│  - Node.js (auth, accounting, bridge services)              │
│  - Python (flowise-proxy service)                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 Technical Implementation

### 1. System Scanner Module

**Purpose**: Verify all prerequisites are met before starting

**Functions**:
```python
def check_docker() -> bool:
    """
    Checks:
    - Docker command available
    - Docker version >= minimum
    - Docker daemon running
    - Docker can execute ps command
    """

def check_python() -> bool:
    """
    Checks:
    - Python version >= 3.8
    - sys module available
    """

def check_git() -> bool:
    """
    Checks:
    - Git command available
    - Git version displayed
    """

def check_drive_space() -> Dict[str, Tuple[float, float]]:
    """
    Returns:
    - Dictionary of all drives
    - Free space and total space for each
    - Warning for drives < 5GB free
    """

def select_data_drive(drives: Dict) -> str:
    """
    Logic:
    - Prefer drives with > 10GB free
    - Select drive with most free space
    - Warn if no drive has sufficient space
    """
```

**Error Handling**:
- Docker not installed → Display download link, exit
- Python too old → Display upgrade instructions, exit
- No drives available → Error message, exit
- All drives < 1GB → Critical warning, allow user choice

---

### 2. Volume Configurator Module

**Purpose**: Configure Docker volumes on optimal drive

**Functions**:
```python
def configure_docker_volumes(data_drive: str):
    """
    Actions:
    - Scan all docker-compose.yml files
    - Replace volume paths with {drive}:/DockerVolumes/...
    - Update flowise, auth, accounting, proxy, bridge
    - Create volume directories
    """
```

**File Updates**:
1. `flowise/docker-compose.yml`
   - `flowise-data:` → `{drive}:/DockerVolumes/flowise-data`
   - `./flowise-postgres` → `{drive}:/DockerVolumes/flowise-postgres`

2. `auth-service/docker-compose.dev.yml`
   - `./mongodb-auth` → `{drive}:/DockerVolumes/mongodb-auth`

3. `accounting-service/docker-compose.yml`
   - `./postgres-accounting` → `{drive}:/DockerVolumes/postgres-accounting`

4. `flowise-proxy-service-py/docker-compose.yml`
   - `./mongodb-proxy` → `{drive}:/DockerVolumes/mongodb-proxy`

5. `bridge/docker-compose.yml`
   - No volumes (static files only)

---

### 3. Secret Generator Module

**Purpose**: Generate cryptographically secure JWT secrets

**Functions**:
```python
def generate_jwt_secrets() -> Tuple[str, str]:
    """
    Uses:
    - secrets module (cryptographically secure)
    - 64-character length
    - Alphanumeric + special chars (-._ )
    
    Returns:
    - access_secret: for access tokens (short-lived)
    - refresh_secret: for refresh tokens (long-lived)
    """
```

**Example Output**:
```
access: II-OYp-J9ydG8K5k1tufUf3CrCu74v6RBoEwwlU5-o.jko-7U.4rei9cJcxSaeh0
refresh: K4.xbCPVjEvJQfvrTOZsG17l_YOmmN8xwQg3hBUKIs3nFZ3K06vjThJ9mqxpl1I_
```

---

### 4. Configuration Manager Module

**Purpose**: Update all .env files with synchronized configuration

**Functions**:
```python
def update_env_file(file_path: str, updates: Dict[str, str]):
    """
    Actions:
    - Read existing .env file (or create new)
    - Parse key=value pairs
    - Update specified keys
    - Preserve comments and formatting
    - Add new keys if not present
    - Write back to file
    """

def configure_all_services(jwt_access, jwt_refresh, flowise_api_key, data_drive):
    """
    Updates:
    - auth-service/.env:
      - JWT_ACCESS_SECRET
      - JWT_REFRESH_SECRET
      - MONGO_URI
    
    - accounting-service/.env:
      - JWT_ACCESS_SECRET
      - JWT_REFRESH_SECRET
      - DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
    
    - flowise-proxy-service-py/.env:
      - JWT_ACCESS_SECRET
      - JWT_REFRESH_SECRET
      - FLOWISE_API_KEY
      - FLOWISE_API_URL
      - MONGODB_URL (with correct password)
    """
```

**Critical**: All three services must have **identical** JWT secrets

---

### 5. Service Orchestrator Module

**Purpose**: Start services in correct order with health checks

**Functions**:
```python
def start_service(service_name: str, wait_time: int) -> bool:
    """
    Steps:
    1. Check if package.json exists
    2. Run npm install if node_modules missing
    3. Execute start.bat or rebuild.bat
    4. Wait specified time for initialization
    5. Return success/failure
    """

def start_flowise() -> bool:
    """
    Special handling:
    - Uses start-with-postgres.bat
    - Polls http://localhost:3002/api/v1/health
    - Max 30 retries (5 seconds each)
    - Returns when healthy or timeout
    """
```

**Startup Order** (critical for dependencies):
1. **Flowise** (3002) - Independent, provides API
2. **Auth Service** (3000) - Depends on MongoDB, provides auth
3. **Accounting Service** (3001) - Depends on PostgreSQL, depends on auth tokens
4. **Flowise Proxy** (8000) - Depends on all above
5. **Bridge UI** (3082) - Depends on proxy

---

### 6. User Provisioner Module

**Purpose**: Create users and allocate initial credits

**Functions**:
```python
def create_admin_user() -> bool:
    """
    Steps:
    1. POST /api/auth/register with admin credentials
    2. Execute MongoDB command to set isVerified:true
    3. Test login to get JWT token
    4. Return success/failure
    """

def create_users_and_allocate_credits(user_list: List[Dict]) -> bool:
    """
    For each user:
    1. POST /api/auth/register
    2. Execute MongoDB command to verify email
    3. POST /api/auth/login to get token
    4. POST /api/credits/allocate with token
    5. Track success/failure
    
    Returns: True if all users created successfully
    """
```

**User List Format**:
```python
users = [
    {
        "username": "admin",
        "email": "admin@example.com",
        "credits": 10000,
        "role": "admin"
    },
    {
        "username": "teacher1",
        "email": "teacher1@example.com",
        "credits": 5000,
        "role": "enduser"
    },
    # ... more users
]
```

**Default User Set**:
- 1 admin: 10,000 credits
- 3 teachers: 5,000 credits each
- 5 students: 1,000 credits each
- **Total**: 30,000 credits allocated

---

### 7. System Verifier Module

**Purpose**: Validate entire system is operational

**Functions**:
```python
def verify_system() -> bool:
    """
    Health Checks:
    1. Docker containers:
       - Count running containers
       - Verify expected containers present
    
    2. API endpoints:
       - Flowise: GET http://localhost:3002/api/v1/health
       - Auth: GET http://localhost:3000/health
       - Accounting: GET http://localhost:3001/health
       - Proxy: GET http://localhost:8000/health
       - Bridge: GET http://localhost:3082
    
    3. Authentication flow:
       - POST http://localhost:8000/api/v1/chat/authenticate
       - Verify access_token received
    
    4. Credit system:
       - GET http://localhost:8000/api/v1/chat/credits
       - Verify totalCredits returned
       - Verify admin has 10,000 credits
    
    Returns:
    - Success if >= 70% checks pass
    - Failure if < 70% checks pass
    """
```

---

### 8. API Client Module

**Purpose**: Make HTTP requests without external dependencies

**Functions**:
```python
def api_request(url: str, method: str, data: Dict, headers: Dict) -> Optional[Dict]:
    """
    Uses:
    - urllib.request (built-in Python library)
    - No external dependencies
    
    Features:
    - Automatic JSON encoding/decoding
    - Error handling and logging
    - Timeout protection (30 seconds)
    - HTTP error code handling
    
    Returns:
    - JSON response as dictionary
    - None if request fails
    """
```

---

## 📋 Debugging Process Summary

### Issues Resolved

#### 1. Drive Space Crisis
**Problem**: C: drive only 1GB free  
**Discovery**: configure_drives.py detected D: drive with 1.9TB  
**Solution**: Automated volume migration to D: drive  
**Impact**: Critical - prevented installation failure

#### 2. MongoDB Connection Failures
**Problem 1**: Auth MongoDB using wrong volume path  
**Discovery**: docker-compose.dev.yml pointed to mongodb-proxy volume  
**Solution**: Updated to mongodb-auth volume  
**Impact**: Auth service couldn't start

**Problem 2**: Flowise-proxy authentication failed  
**Discovery**: .env password didn't match docker-compose  
**Solution**: Synchronized passwords  
**Impact**: Proxy couldn't connect to database

#### 3. JWT Secret Mismatch
**Problem**: Accounting service couldn't verify auth tokens  
**Discovery**: accounting/.env had placeholder secrets  
**Solution**: Generated and synchronized secrets across all services  
**Impact**: Critical - cross-service auth completely broken

#### 4. Email Verification Field
**Problem**: Admin couldn't login despite being verified  
**Discovery**: Code checks `isVerified`, DB had `emailVerified`  
**Solution**: Updated MongoDB to use `isVerified` field  
**Impact**: User login impossible

#### 5. Missing package-lock.json
**Problem**: Docker builds failed for Node services  
**Discovery**: package-lock.json not committed to repo  
**Solution**: Run `npm install` before docker build  
**Impact**: Service builds failed

#### 6. Credit System Initialization
**Problem**: Users had no credits after creation  
**Discovery**: Credit system requires explicit allocation  
**Solution**: Automated credit allocation via API  
**Impact**: System not usable for testing

---

## ✅ Success Criteria

### Functional Requirements
- [x] Complete setup in < 15 minutes
- [x] Single command execution (automated_setup.bat)
- [x] All 9 containers running and healthy
- [x] Admin user with 10,000 credits
- [x] 8 additional users with appropriate credits
- [x] All API endpoints responding
- [x] Bridge UI accessible
- [x] Authentication working end-to-end
- [x] Credit system functional

### Non-Functional Requirements
- [x] User-friendly error messages
- [x] Progress feedback at each step
- [x] Automatic error recovery where possible
- [x] Clear success/failure indication
- [x] Comprehensive logging
- [x] Documentation for troubleshooting

---

## 🔮 Future Enhancements

### Phase 2: Cross-Platform Support
- [ ] Linux support (bash script wrapper)
- [ ] macOS support (zsh script wrapper)
- [ ] Docker volume detection for non-Windows

### Phase 3: Advanced Features
- [ ] Interactive mode (customize users/credits)
- [ ] Backup/restore automation
- [ ] System upgrade automation
- [ ] Health monitoring dashboard
- [ ] Log aggregation and analysis

### Phase 4: CI/CD Integration
- [ ] GitHub Actions workflow
- [ ] Automated testing suite
- [ ] Docker image pre-building
- [ ] Environment templates

---

## 📚 Related Documentation

- `DEBUGGING_PROGRESS.md` - Complete debugging journey
- `SYSTEM_STATUS.md` - Current system state and configuration
- `PULL_REQUEST.md` - Changes and improvements for upstream
- `README.md` - User-facing setup instructions
- `CONTRIBUTING.md` - Development guidelines

---

## 🎓 Lessons Learned

### Configuration Management
- **Lesson**: Microservices require synchronized configuration
- **Solution**: Automated secret generation and distribution
- **Best Practice**: Single source of truth for secrets

### Database Field Naming
- **Lesson**: Field names must match between code and database
- **Solution**: Automated data verification during setup
- **Best Practice**: Schema validation in CI/CD

### Docker Volume Management
- **Lesson**: Windows drive selection requires explicit paths
- **Solution**: Automatic drive detection and selection
- **Best Practice**: Never assume default volume location

### Service Dependencies
- **Lesson**: Services must start in specific order
- **Solution**: Orchestrated startup with health checks
- **Best Practice**: Document and automate dependency order

### User Onboarding
- **Lesson**: Initial credit allocation is critical for testing
- **Solution**: Automated user and credit provisioning
- **Best Practice**: Include sample data in setup

---

## 🏆 Achievement

**Before**: 2-3 hours of manual, error-prone setup  
**After**: 10-15 minutes of automated, validated setup  
**Improvement**: 90% time reduction, near-zero error rate  
**User Experience**: Dramatically improved - from frustrating to effortless

---

**Status**: ✅ Complete and Production-Ready  
**Last Updated**: February 12, 2026  
**Maintainer**: @vocabbreaker
