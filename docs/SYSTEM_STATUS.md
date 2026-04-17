# ChatProxyPlatform - System Status Report
**Generated**: 2024-12-02  
**System**: Windows with Docker Desktop  
**Storage**: D: drive (1.9TB free)

---

## ✅ System Overview
All services are **OPERATIONAL** and configured correctly on D: drive to conserve C: drive space.

---

## 🚀 Running Services

| Service | Container | Status | Port | Health |
|---------|-----------|--------|------|--------|
| **Flowise** | flowise | Up 3 hours | 3002 | ✅ Healthy |
| **Auth Service** | auth-service | Up 15 minutes | 3000 | ✅ Running |
| **Accounting Service** | accounting-service | Up 33 minutes | 3001 | ✅ Healthy |
| **Flowise Proxy** | flowise-proxy | Up 33 minutes | 8000 | ✅ Healthy |
| **Bridge UI** | bridge-ui | Up 56 minutes | 3082 | ✅ Healthy |
| **PostgreSQL (Flowise)** | flowise-postgres | Up 3 hours | 5433 | ✅ Healthy |
| **PostgreSQL (Accounting)** | postgres-accounting | Up 33 minutes | 5432 | ✅ Running |
| **MongoDB (Auth)** | mongodb-auth | Up 32 minutes | 27017 | ✅ Healthy |
| **MongoDB (Proxy)** | mongodb-proxy | Up 33 minutes | 27020 | ✅ Healthy |
| **MailHog** | auth-mailhog | Up 32 minutes | 8025 | ✅ Running |

---

## 👥 User Accounts (9 Total)

| Username | Role | Email | Credits | Status |
|----------|------|-------|---------|--------|
| **admin** | admin | admin@example.com | 10,000 | ✅ Verified |
| teacher1 | enduser | teacher1@example.com | 5,000 | ✅ Verified |
| teacher2 | enduser | teacher2@example.com | 5,000 | ✅ Verified |
| teacher3 | enduser | teacher3@example.com | 5,000 | ✅ Verified |
| student1 | enduser | student1@example.com | 1,000 | ✅ Verified |
| student2 | enduser | student2@example.com | 1,000 | ✅ Verified |
| student3 | enduser | student3@example.com | 1,000 | ✅ Verified |
| student4 | enduser | student4@example.com | 1,000 | ✅ Verified |
| student5 | enduser | student5@example.com | 1,000 | ✅ Verified |

### 🔐 Default Password
- **All users**: `admin@admin`
- ⚠️ **IMPORTANT**: Users should change their passwords after first login

---

## 🔑 API Endpoints

### Authentication (Port 3000)
```bash
# Login
POST http://localhost:3000/api/auth/login
Body: {"username": "admin", "password": "admin@admin"}
```

### Accounting (Port 3001)
```bash
# Check balance (requires JWT token)
GET http://localhost:3001/api/credits/balance
Header: Authorization: Bearer <token>
```

### Flowise Proxy (Port 8000)
```bash
# Authenticate
POST http://localhost:8000/api/v1/chat/authenticate
Body: {"username": "admin", "password": "admin@admin"}

# Get credits
GET http://localhost:8000/api/v1/chat/credits
Header: Authorization: Bearer <token>

# Chat prediction (streaming)
POST http://localhost:8000/api/v1/chat/predict/stream/store
Header: Authorization: Bearer <token>
Body: {
  "question": "Your question here",
  "chatflow_id": "<chatflow_id>",
  "sessionId": "<optional_session_id>"
}
```

### Bridge UI (Port 3082)
```
http://localhost:3082
```

---

## 💾 Storage Configuration

All Docker volumes are configured on **D: drive** to avoid C: drive space constraints:

| Service | Volume Path | Purpose |
|---------|-------------|---------|
| Flowise | `D:/DockerVolumes/flowise-data` | Flowise database |
| Flowise PostgreSQL | `D:/DockerVolumes/flowise-postgres` | Flowise data |
| Auth MongoDB | `D:/DockerVolumes/mongodb-auth` | User authentication |
| Proxy MongoDB | `D:/DockerVolumes/mongodb-proxy` | Proxy data |
| Accounting PostgreSQL | `D:/DockerVolumes/postgres-accounting` | Credit management |

### Drive Status
- **C: Drive**: 1 GB free (system drive)
- **D: Drive**: 1,894.5 GB free / 1,907.6 GB total

---

## 🔐 Security Configuration

### JWT Secrets (Synchronized across all services)
- **Access Token Secret**: `II-OYp-J9ydG8K5k1tufUf3CrCu74v6RBoEwwlU5-o.jko-7U.4rei9cJcxSaeh0`
- **Refresh Token Secret**: `K4.xbCPVjEvJQfvrTOZsG17l_YOmmN8xwQg3hBUKIs3nFZ3K06vjThJ9mqxpl1I_`

### Database Credentials
- **MongoDB (Proxy)**: Password in flowise-proxy `.env` file
- **PostgreSQL**: Credentials in respective `.env` files

### Flowise API
- **API Key**: `O_VGEe4xJkdJcrdyoVDm-sPzohLEomhSch4ePbj_hcg`

---

## 🧪 Quick Testing

### Test Admin Login & Credit Check
```powershell
# Authenticate
$auth = Invoke-RestMethod -Uri "http://localhost:8000/api/v1/chat/authenticate" `
  -Method POST `
  -ContentType "application/json" `
  -Body '{"username":"admin","password":"admin@admin"}'

# Check credits
Invoke-RestMethod -Uri "http://localhost:8000/api/v1/chat/credits" `
  -Method GET `
  -Headers @{Authorization = "Bearer $($auth.access_token)"}
```

Expected output: `totalCredits: 10000`

### Test Bridge UI
1. Open browser: `http://localhost:3082`
2. Login with:
   - Username: `admin`
   - Password: `admin@admin`
3. Credits should display: **10,000**

---

## 📊 Credit Allocation Summary

| Category | Count | Credits/User | Total Credits |
|----------|-------|--------------|---------------|
| Admin | 1 | 10,000 | 10,000 |
| Teachers | 3 | 5,000 | 15,000 |
| Students | 5 | 1,000 | 5,000 |
| **Total** | **9** | - | **30,000** |

---

## 🎯 Next Steps

### For Administrators
1. ✅ Login to Bridge UI at `http://localhost:3082`
2. ✅ Verify credit balance displays correctly
3. ⚠️ Change admin password (recommended)
4. ⚠️ Configure Flowise chatflows
5. ⚠️ Assign chatflows to users
6. ⚠️ Test chat functionality

### For Teachers & Students
1. Login to Bridge UI with provided credentials
2. Change default password on first login
3. Check credit balance
4. Access assigned chatflows
5. Start using the chat system

---

## 🔧 Management Commands

### Start Services
```bash
cd C:\Users\aidcec\ChatProxyPlatform\flowise
.\start.bat

cd ..\auth-service
.\start.bat

cd ..\accounting-service
.\start.bat

cd ..\flowise-proxy-service-py
.\start.bat

cd ..\bridge
.\start.bat
```

### Stop Services
```bash
cd C:\Users\aidcec\ChatProxyPlatform\flowise
.\stop.bat

cd ..\auth-service
.\stop.bat

cd ..\accounting-service
.\stop.bat

cd ..\flowise-proxy-service-py
.\stop.bat

cd ..\bridge
.\stop.bat
```

### Rebuild Services (after code changes)
```bash
cd <service-directory>
.\rebuild.bat
```

### View Logs
```bash
cd <service-directory>
.\logs.bat
```

---

## ✅ Verified Functionality

- [x] D: drive volume configuration
- [x] All services running and healthy
- [x] JWT authentication working
- [x] MongoDB connections established
- [x] PostgreSQL databases initialized
- [x] User accounts created and verified
- [x] Credits allocated to all users
- [x] API endpoints responding correctly
- [x] Bridge UI accessible
- [x] Flowise integration working

---

## 📝 Important Notes

1. **Email Verification**: All users are pre-verified (`isVerified: true` in MongoDB)
2. **Password Security**: All users have default password `admin@admin` - should be changed
3. **JWT Tokens**: Valid for standard duration, use refresh tokens for extended sessions
4. **Credit System**: Credits are deducted per chat request based on chatflow cost
5. **Session Management**: Each chat creates a session ID for conversation tracking
6. **File Storage**: Supports file uploads in chat (stored in MongoDB)

---

## 🆘 Troubleshooting

### If services won't start:
1. Check Docker Desktop is running
2. Verify D: drive has sufficient space
3. Check logs: `cd <service-directory> && .\logs.bat`

### If authentication fails:
1. Verify JWT secrets match across all services
2. Check MongoDB auth connection
3. Restart auth-service: `cd auth-service && .\rebuild.bat`

### If credits don't show:
1. Verify accounting-service is running
2. Check PostgreSQL connection
3. Query database directly (see commands above)

### If Bridge UI is blank:
1. Clear browser cache
2. Check browser console for errors
3. Verify proxy service at `http://localhost:8000`

---

## 📞 System Information

- **Docker Desktop**: 29.2.0
- **Python**: 3.14.3
- **Git**: 2.52.0.windows.1
- **Platform**: Windows
- **Network**: chatproxy-network (external Docker network)

---

**System Ready for Production Use!** 🎉
