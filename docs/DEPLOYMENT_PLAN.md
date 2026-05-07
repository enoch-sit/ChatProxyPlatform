# Complete Deployment Plan - Fresh Windows Installation

**Target Audience:** Non-technical users (teachers, administrators)  
**Estimated Time:** 45-60 minutes  
**Prerequisites:** Windows 10/11, Administrator access

---

## Overview

This guide will help you set up the ChatProxy Platform on a completely fresh Windows computer. By the end, you'll have:

- ✅ A working AI chatbot platform
- ✅ Admin account with full access
- ✅ Teacher and student accounts ready to use
- ✅ Your first AI chatflow configured
- ✅ Optional SSL certificate for secure connections

---

## Phase 1: System Prerequisites (15 minutes)

### Step 1.1: Install Docker Desktop

**What is Docker?** Think of it as a "container" that runs all the software pieces together.

1. **Download Docker Desktop:**
   - Open your web browser
   - Go to: https://www.docker.com/products/docker-desktop
   - Click "Download for Windows"
   - Wait for download to complete (~500 MB)

2. **Install Docker Desktop:**
   - Double-click the downloaded file `Docker Desktop Installer.exe`
   - Click "OK" when asked about WSL 2
   - Wait for installation (~5-10 minutes)
   - Click "Close and restart" when done
   - **Your computer will restart**

3. **After Restart:**
   - Docker Desktop will start automatically
   - Accept the service agreement
   - Skip the tutorial (or complete it if you want)
   - Wait until you see "Docker Desktop is running" (green icon in taskbar)

**How to verify:** Open Command Prompt (search "cmd" in Windows) and type:
```batch
docker --version
```
You should see something like: `Docker version 24.0.7`

---

### Step 1.2: Install Git (Optional but Recommended)

**What is Git?** A tool to download the code from the internet.

1. **Download Git:**
   - Go to: https://git-scm.com/download/win
   - Click "64-bit Git for Windows Setup"
   - Wait for download

2. **Install Git:**
   - Double-click the downloaded file
   - Click "Next" for all options (use defaults)
   - Wait for installation
   - Click "Finish"

**How to verify:** Open Command Prompt and type:
```batch
git --version
```
You should see something like: `git version 2.43.0`

---

### Step 1.3: Install Python (Required)

**What is Python?** A programming language needed for setup scripts.

1. **Download Python:**
   - Go to: https://www.python.org/downloads/
   - Click "Download Python 3.12.x" (latest version)
   - Wait for download

2. **Install Python:**
   - Double-click the downloaded file
   - ⚠️ **IMPORTANT:** Check "Add Python to PATH" at bottom
   - Click "Install Now"
   - Wait for installation
   - Click "Close"

**How to verify:** Open Command Prompt and type:
```batch
python --version
```
You should see something like: `Python 3.12.1`

---

### Step 1.4: Run System Check

1. **Download the project:**
   - Open Command Prompt
   - Type:
     ```batch
     cd C:\Users\%USERNAME%\Documents
     git clone https://github.com/YOUR_REPO/ThankGodForChatProxyPlatform.git
     cd ThankGodForChatProxyPlatform
     ```
   
   **OR if you have a USB/download:**
   - Copy the entire folder to `C:\Users\%USERNAME%\Documents\`

2. **Run the system checker:**
   ```batch
   cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform
   check_system.bat
   ```

**What it checks:**
- ✅ Docker installed and running
- ✅ Python installed
- ✅ Git installed (optional)
- ✅ Ports available (3000, 3001, 3002, 3082, 8000)
- ✅ Disk space (needs ~5 GB free)

**If any checks fail:** Follow the on-screen instructions to fix them.

---

## Phase 2: SSL Certificate Setup (Optional, 10 minutes)

**Do you need SSL?** Only if you want HTTPS (secure) connections. For local testing, you can skip this.

### Step 2.1: Check for Existing SSL Certificate

Do you have a `.pfx` or `.pem` certificate file?
- **YES** → Continue to Step 2.2
- **NO** → Skip to Phase 3 (you can add SSL later)

---

### Step 2.2: Configure SSL Certificate

1. **Copy your certificate files:**
   ```batch
   # If you have .pfx file:
   copy YOUR_CERTIFICATE.pfx C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\nginx\certs\
   
   # If you have .pem files:
   copy certificate.pem C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\nginx\certs\
   copy private-key.pem C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\nginx\certs\
   ```

2. **Update nginx configuration:**
   - The system will auto-detect your certificate
   - Or manually edit: `nginx\nginx.conf`

3. **Start nginx:**
   ```batch
   cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\nginx
   start_nginx.bat
   ```

**Access URLs with SSL:**
- Bridge UI: https://localhost (or https://localhost:3082)
- Flowise: https://localhost:3002
- Auth API: https://localhost:3000

**Without SSL (simpler):**
- Bridge UI: http://localhost:3082
- Flowise: http://localhost:3002
- Auth API: http://localhost:3000

---

## Phase 3: Launch Services (15 minutes)

### Step 3.1: Start Flowise

**What is Flowise?** The AI flow builder where you create chatbots.

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\flowise
start-with-postgres.bat
```

**Wait for:** "✓ Container flowise Started" (~30-60 seconds)

**Open Flowise:** http://localhost:3002

**First-time setup:**
1. You'll see "Create Admin Account" screen
2. Fill in:
   - **Username:** `admin`
   - **Email:** `admin@admin.com`
   - **Password:** `Test@1234`
3. Click "Create Account"
4. You're now logged in to Flowise!

---

### Step 3.2: Start Auth Service

**What is Auth Service?** Manages user logins and permissions.

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\auth-service
start.bat
```

**Wait for:** "Auth Service: http://localhost:3000" (~30 seconds)

---

### Step 3.3: Start Accounting Service

**What is Accounting Service?** Tracks AI usage credits.

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\accounting-service
start_docker.bat
```

**Wait for:** "Accounting service started" (~30 seconds)

---

### Step 3.4: Start Flowise Proxy Service

**What is Flowise Proxy?** Connects everything together.

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\flowise-proxy-service-py
docker-compose up -d
```

**Wait for:** "Container flowise-proxy Started" (~20 seconds)

---

### Step 3.5: Start Bridge UI (Frontend)

**What is Bridge UI?** The web interface users will see.

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\bridge
start.bat
```

**Wait for:** "Bridge UI started at http://localhost:3082" (~10 seconds)

---

### Step 3.6: Verify All Services Running

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform
check_system.bat
```

Look for:
```
✅ All required services are running:
   ✓ flowise (port 3002)
   ✓ auth-service (port 3000)
   ✓ accounting-service (port 3001)
   ✓ flowise-proxy (port 8000)
   ✓ bridge-ui (port 3082)
```

---

## Phase 4: Configure Flowise API Key (5 minutes)

### Step 4.1: Generate Flowise API Key

1. **Open Flowise:** http://localhost:3002
2. **Login:**
   - Email: `admin@admin.com`
   - Password: `Test@1234`
3. **Navigate to Settings:**
   - Click your profile icon (top-right)
   - Click "Settings"
   - Click "API Keys" tab
4. **Generate Key:**
   - Click "Add New Key" button
   - Copy the generated key (looks like: `x1LLhKIW8TGesY2fJDJonjPMZL...`)
   - ⚠️ **Save this key!** You'll need it in the next step

---

### Step 4.2: Configure Flowise Proxy with API Key

1. **Open configuration file:**
   ```batch
   cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\flowise-proxy-service-py
   notepad .env
   ```

2. **Find this line:**
   ```
   FLOWISE_API_KEY=
   ```

3. **Paste your API key:**
   ```
   FLOWISE_API_KEY=x1LLhKIW8TGesY2fJDJonjPMZL_wqzKTL-eM8wqmrAM
   ```

4. **Save and close** Notepad (File → Save)

5. **Restart Flowise Proxy:**
   ```batch
   docker-compose restart
   ```

**Wait for:** ~10 seconds

---

## Phase 5: Create Admin and Users (10 minutes)

### Step 5.1: Create Admin Account in Auth Service

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\auth-service\quickCreateAdminPy
setup_and_run.bat
```

**Wait for:** "✅ Admin account created successfully"

**Admin Credentials:**
- Username: `admin`
- Email: `admin@example.com`
- Password: `admin@admin`

---

### Step 5.2: Setup Admin User in All Systems

This connects the admin account across all services:

```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForJesusChrist\ThankGodForChatProxyPlatform\flowise-proxy-service-py
docker exec flowise-proxy python /tmp/sync_admin_chatflows.py
```

**Wait for:** "✅ SETUP COMPLETE! User: admin, Chatflows: X, Credits: 5000"

---

### Step 5.3: Create Teacher and Student Accounts

**Open the users file:**
```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\auth-service\quickCreateAdminPy
notepad users.csv
```

**Example users.csv:**
```csv
action,username,email,password,role,fullName,credits
create,teacher1,teacher1@school.com,Teacher1!,teacher,John Teacher,5000
create,teacher2,teacher2@school.com,Teacher2!,teacher,Jane Teacher,5000
create,student1,student1@school.com,Student1!,student,Alice Student,1000
create,student2,student2@school.com,Student2!,student,Bob Student,1000
create,student3,student3@school.com,Student3!,student,Carol Student,1000
```

**Save the file** (File → Save)

**Apply the changes:**
```batch
sync_all_users.bat
```

**Wait for:** "✅ SUCCESS! All users and credits synchronized"

---

## Phase 6: Create Your First Chatflow (10 minutes)

### Step 6.1: Login to Flowise

1. Open http://localhost:3002
2. Login with admin credentials:
   - Email: `admin@admin.com`
   - Password: `Test@1234`

---

### Step 6.2: Create a Simple Chat Assistant

1. **Click "Add New" (+ button)**

2. **Name your chatflow:**
   - Name: `My First Assistant`
   - Description: `A helpful AI assistant for students`
   - Click "Create"

3. **Drag and drop components:**
   
   **Step 1 - Add Chat Model:**
   - Click "Chat Models" in left sidebar
   - Drag "ChatOpenAI" to canvas
   - Configure:
     - Model Name: `gpt-3.5-turbo`
     - Temperature: `0.7`
     - OpenAI API Key: *[Enter your OpenAI key]*
   
   **Step 2 - Add Memory:**
   - Click "Memory" in left sidebar
   - Drag "Buffer Memory" to canvas
   - Connect it to ChatOpenAI (drag from circle to circle)
   
   **Step 3 - Add Conversational Chain:**
   - Click "Chains" in left sidebar
   - Drag "Conversation Chain" to canvas
   - Connect:
     - Chat Model → Connect to ChatOpenAI
     - Memory → Connect to Buffer Memory

4. **Save your chatflow:**
   - Click "💾 Save" button (top-right)
   - Click "Deploy" button
   - You'll see: "Chatflow deployed successfully!"

5. **Test your chatflow:**
   - Click "💬 Test" button (top-right)
   - Type: "Hello, who are you?"
   - The AI should respond!

---

### Step 6.3: Make Chatflow Available to Users

**Automatic sync:**
The chatflow is automatically available to all users through the Bridge UI!

**Manual sync (if needed):**
```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\flowise-proxy-service-py
docker exec flowise-proxy python /tmp/sync_admin_chatflows.py
```

---

## Phase 7: Test the Complete System (5 minutes)

### Step 7.1: Login as Admin

1. **Open Bridge UI:** http://localhost:3082
2. **Login:**
   - Username: `admin`
   - Password: `admin@admin`
3. **You should see:**
   - Dashboard with available chatflows
   - "My First Assistant" chatflow
   - Credit balance: 5000 credits

---

### Step 7.2: Test Chat Functionality

1. **Click on "My First Assistant"**
2. **Type a message:** "Hello! Can you help me with my homework?"
3. **Verify:**
   - AI responds correctly
   - Credit counter decreases
   - Chat history is saved

---

### Step 7.3: Login as Student

1. **Logout** (click profile → Logout)
2. **Login as student:**
   - Username: `student1`
   - Password: `Student1!`
3. **Verify:**
   - Can see chatflows
   - Has 1000 credits
   - Can chat with AI

---

## Phase 8: Daily Management (Ongoing)

### Managing Users and Credits

**Quick reference:**

1. **Edit users:**
   ```batch
   cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform\auth-service\quickCreateAdminPy
   notepad users.csv
   ```

2. **Apply changes:**
   ```batch
   sync_all_users.bat
   ```

**Common tasks:**

- **Add student:** Add row with `create,username,email,password,student,Name,1000`
- **Add teacher:** Add row with `create,username,email,password,teacher,Name,5000`
- **Remove user:** Change `create` to `delete`
- **Update credits:** Change the number in credits column
- **Change password:** Update password column

**Then run:** `sync_all_users.bat`

---

### Starting/Stopping Services

**Stop all services:**
```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform
stop_all_services.bat
```

**Start all services:**
```batch
cd C:\Users\%USERNAME%\Documents\ThankGodForChatProxyPlatform
start_all_services.bat
```

**Check system status:**
```batch
check_system.bat
```

---

### Backup Your Data

**Important files to backup weekly:**

1. **Users and credits:**
   ```
   auth-service\quickCreateAdminPy\users.csv
   ```

2. **Database backup:**
   ```batch
   backup_databases.bat
   ```
   Saves to: `backups\[date]\`

3. **Flowise flows:**
   - Export from Flowise UI (Settings → Export)
   - Save to: `backups\flowise-flows\`

---

## Troubleshooting

### Services Won't Start

**Run diagnostics:**
```batch
check_system.bat
```

**Common issues:**

1. **Docker not running:**
   - Open Docker Desktop
   - Wait until icon is green
   - Try again

2. **Port already in use:**
   ```batch
   netstat -ano | findstr :3000
   netstat -ano | findstr :3001
   netstat -ano | findstr :3002
   netstat -ano | findstr :3082
   netstat -ano | findstr :8000
   ```
   - Kill conflicting processes
   - Or restart computer

3. **Not enough disk space:**
   - Free up at least 5 GB
   - Run: `docker system prune -a`

---

### Chatflows Not Syncing

1. **Check Flowise API key:**
   ```batch
   cd flowise-proxy-service-py
   notepad .env
   ```
   Verify `FLOWISE_API_KEY` is set

2. **Manual sync:**
   ```batch
   docker exec flowise-proxy python /tmp/sync_admin_chatflows.py
   ```

3. **Check logs:**
   ```batch
   docker logs flowise-proxy --tail 50
   ```

---

### Users Can't Login

1. **Verify user exists:**
   ```batch
   cd auth-service\quickCreateAdminPy
   list_users.bat
   ```

2. **Check user status:**
   ```batch
   test_login.bat
   ```

3. **Re-sync users:**
   ```batch
   sync_all_users.bat
   ```

---

### AI Not Responding

1. **Check OpenAI API key in Flowise:**
   - Login to Flowise
   - Open your chatflow
   - Verify API key is correct

2. **Check credits:**
   - Login to Bridge UI
   - Check credit balance > 0

3. **Check Flowise Proxy:**
   ```batch
   docker logs flowise-proxy --tail 50
   ```

---

## Security Recommendations

### For Production Use:

1. **Change default passwords:**
   - Admin password: `admin@admin` → Strong password
   - Flowise password: Replace the initial setup password with a strong password and store it securely

2. **Update JWT secrets:**
   ```batch
   cd auth-service
   notepad .env
   ```
   Change `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET`

3. **Enable HTTPS:**
   - Follow Phase 2 (SSL Setup)
   - Use real SSL certificates (not self-signed)

4. **Firewall:**
   - Only open necessary ports
   - Use Windows Firewall rules

5. **Backups:**
   - Daily backup of users.csv
   - Weekly backup of databases
   - Monthly full system backup

---

## Getting Help

### Log Files

**Check logs when issues occur:**

```batch
# All services
docker ps -a

# Specific service
docker logs flowise
docker logs auth-service
docker logs flowise-proxy
docker logs accounting-service
docker logs bridge-ui
```

---

### System Health Check

**Run anytime:**
```batch
check_system.bat
```

**Shows:**
- ✅ Service status
- ✅ Port availability
- ✅ Disk space
- ✅ Docker status
- ✅ API connectivity
- ✅ Database status
- ✅ User count
- ✅ Chatflow count

---

## Quick Reference Card

**Print this and keep it handy!**

### Service URLs
- **Bridge UI (Students/Teachers):** http://localhost:3082
- **Flowise (Admin):** http://localhost:3002
- **MailHog (Email testing):** http://localhost:8025

### Default Credentials
- **Admin:** admin / admin@admin
- **Flowise Admin:** admin@admin.com / Test@1234

### Essential Commands
```batch
# Check system
check_system.bat

# Start all services
start_all_services.bat

# Stop all services
stop_all_services.bat

# Manage users
cd auth-service\quickCreateAdminPy
notepad users.csv
sync_all_users.bat

# Backup data
backup_databases.bat
```

### Emergency Reset
```batch
# Stop everything
stop_all_services.bat

# Remove all data (⚠️ DELETES EVERYTHING)
docker-compose down -v

# Start fresh
start_all_services.bat
```

---

## Completion Checklist

Print this and check off each item:

```
Phase 1: Prerequisites
□ Docker Desktop installed and running
□ Python installed and in PATH
□ Git installed (optional)
□ check_system.bat runs successfully
□ All ports available (3000, 3001, 3002, 3082, 8000)

Phase 2: SSL (Optional)
□ SSL certificate copied to nginx/certs/
□ nginx started
□ HTTPS URLs accessible

Phase 3: Services
□ Flowise running (http://localhost:3002)
□ Auth service running (http://localhost:3000)
□ Accounting service running (http://localhost:3001)
□ Flowise proxy running (http://localhost:8000)
□ Bridge UI running (http://localhost:3082)

Phase 4: Configuration
□ Flowise admin account created
□ Flowise API key generated
□ API key added to flowise-proxy .env
□ Flowise proxy restarted

Phase 5: Users
□ Admin account created in auth service
□ Admin user synced across all systems
□ Teacher accounts created
□ Student accounts created
□ All users verified with list_users.bat

Phase 6: First Chatflow
□ Chatflow created in Flowise
□ Chatflow deployed
□ Chatflow tested in Flowise
□ Chatflow visible in Bridge UI

Phase 7: Testing
□ Admin login successful
□ Admin can see chatflows
□ Admin can chat with AI
□ Student login successful
□ Student can see chatflows
□ Student can chat with AI
□ Credits decrease after chat

Phase 8: Documentation
□ Backup schedule created
□ users.csv backed up
□ Admin passwords documented (securely!)
□ Quick reference card printed
```

---

**🎉 Congratulations!**

You've successfully deployed the complete ChatProxy Platform!

**Next steps:**
- Create more chatflows in Flowise
- Add more students and teachers
- Configure backup schedule
- Customize for your institution

**Support:** Keep this guide and the Quick Reference Card handy for daily operations.
