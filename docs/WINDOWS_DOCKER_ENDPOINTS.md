# Windows Docker Endpoints Configuration

## Service Network Map

All services are connected through the `chatproxy-network` Docker network.

---

## 📍 External Access Ports (Windows Host)

| Service | Port | Access URL |
|---------|------|------------|
| **Bridge UI** | 3082 | http://localhost:3082 |
| **Flowise Proxy API** | 8000 | http://localhost:8000 |
| **Auth Service** | 3000 | http://localhost:3000 |
| **Accounting Service** | 3001 | http://localhost:3001 |
| **Flowise** | 3002 | http://localhost:3002 |
| **MongoDB (Auth)** | 27017 | mongodb://localhost:27017 |
| **MongoDB (Proxy)** | 27020 | mongodb://localhost:27020 |
| **PostgreSQL (Accounting)** | 5432 | postgresql://localhost:5432 |
| **PostgreSQL (Flowise)** | 5433 | postgresql://localhost:5433 |
| **MailHog (SMTP)** | 1025 | smtp://localhost:1025 |
| **MailHog (Web UI)** | 8025 | http://localhost:8025 |

---

## 🔗 Internal Docker Network Endpoints

### Bridge UI → Flowise Proxy
```yaml
# bridge/docker-compose.yml
environment:
  - VITE_FLOWISE_PROXY_API_URL=${FLOWISE_PROXY_URL:-http://host.docker.internal:8000}
```
**Note:** Bridge UI uses `host.docker.internal:8000` to access Flowise Proxy from browser.

---

### Flowise Proxy → Other Services

```yaml
# flowise-proxy-service-py/docker-compose.yml
environment:
  # Flowise API (Container-to-Container)
  - FLOWISE_API_URL=${FLOWISE_API_URL:-http://flowise:3000}
  
  # Auth Service (Container-to-Container)
  - EXTERNAL_AUTH_URL=${EXTERNAL_AUTH_URL:-http://auth-service:3000/api}
  
  # Accounting Service (Container-to-Container)
  - ACCOUNTING_SERVICE_URL=${ACCOUNTING_SERVICE_URL:-http://accounting-service:3001/api}
  
  # MongoDB (Container-to-Container)
  - MONGODB_URL=${MONGODB_URL}  # mongodb://admin:password@mongodb:27017/flowise_proxy
```

**Current .env Configuration:**
```env
FLOWISE_API_URL=https://aai03.eduhk.hk  # External Flowise instance
EXTERNAL_AUTH_URL=http://auth-service:3000/api
ACCOUNTING_SERVICE_URL=http://accounting-service:3001/api
```

---

### Auth Service → MongoDB

```yaml
# auth-service/docker-compose.dev.yml
depends_on:
  - mongodb

# Connects to: mongodb://mongodb-auth:27017/auth_db
```

---

### Accounting Service → PostgreSQL

```yaml
# accounting-service/docker-compose.yml
environment:
  - DB_HOST=postgres-accounting
  - DB_PORT=5432

# Connects to: postgresql://postgres-accounting:5432/accounting_db
```

---

## ✅ Endpoint Alignment Status

### Bridge UI Frontend → Flowise Proxy Backend

| Frontend Endpoint | Backend Route | Status |
|-------------------|---------------|--------|
| `POST /api/v1/chat/authenticate` | ✅ auth_routes.py | ✅ Aligned |
| `POST /api/v1/chat/refresh` | ✅ auth_routes.py | ✅ Aligned |
| `POST /api/v1/chat/predict/stream/store` | ✅ predict_routes.py | ✅ Aligned |
| `GET /api/v1/chat/sessions` | ✅ session_routes.py | ✅ Aligned |
| `GET /api/v1/chat/sessions/{id}/history` | ✅ session_routes.py | ✅ Aligned |
| `POST /api/v1/admin/chatflows/sync` | ✅ admin.py | ✅ Aligned |
| `GET /api/v1/admin/chatflows` | ✅ admin.py | ✅ Aligned |
| `GET /api/v1/admin/chatflows/{id}` | ✅ admin.py | ✅ Aligned |
| `POST /api/v1/admin/chatflows/{id}/users` | ✅ admin.py | ✅ Aligned |
| `DELETE /api/v1/admin/chatflows/{id}/users` | ✅ admin.py | ✅ Aligned |

### File Upload Handling

**Frontend:** Sends files inline in the predict request body
```typescript
// bridge/src/api/chat.ts
requestBody.uploads = files.map(file => ({
  data: file.data,  // Base64 data URL
  type: "file",
  name: file.name,
  mime: file.type
}));
```

**Backend:** Accepts files in the predict request
```python
# flowise-proxy-service-py/app/api/predict_routes.py
class ChatRequest(BaseModel):
    uploads: Optional[List[FileUpload]] = None
```

✅ **File uploads are aligned** - no separate `/upload` endpoint needed.

---

## 🌐 Network Configuration

### Bridge Network
```yaml
networks:
  bridge-network:
    driver: bridge
```
- Isolated network for Bridge UI
- No communication with other services (frontend-only)

### ChatProxy Network
```yaml
networks:
  chatproxy-network:
    external: true
```
- Shared network for all backend services
- Must be created before starting services:
  ```batch
  docker network create chatproxy-network
  ```

### Service-Specific Networks
- **flowise-network**: Flowise + MongoDB (Proxy) + Flowise Proxy
- **auth-network**: Auth Service + MongoDB (Auth)
- **accounting-network**: Accounting Service + PostgreSQL (Accounting)

---

## 🔒 Environment Variable Override

### For Local Development (Windows Host → Container)
```env
# flowise-proxy-service-py/.env
FLOWISE_API_URL=http://host.docker.internal:3002
EXTERNAL_AUTH_URL=http://host.docker.internal:3000/api
ACCOUNTING_SERVICE_URL=http://host.docker.internal:3001/api
```

### For Container-to-Container (Production)
```env
# flowise-proxy-service-py/.env
FLOWISE_API_URL=http://flowise:3000
EXTERNAL_AUTH_URL=http://auth-service:3000/api
ACCOUNTING_SERVICE_URL=http://accounting-service:3001/api
```

---

## 🚀 Startup Order

1. **Create Network First:**
   ```batch
   docker network create chatproxy-network
   ```

2. **Start Services in Order:**
   ```batch
   # 1. Auth Service (includes MongoDB)
   cd auth-service
   start.bat

   # 2. Accounting Service (includes PostgreSQL)
   cd accounting-service
   start.bat

   # 3. Flowise (includes PostgreSQL)
   cd flowise
   start.bat

   # 4. Flowise Proxy (includes MongoDB)
   cd flowise-proxy-service-py
   start.bat

   # 5. Bridge UI
   cd bridge
   start.bat
   ```

3. **Verify All Services:**
   ```batch
   docker ps
   ```
   Should show 10 containers running:
   - bridge-ui
   - flowise-proxy
   - mongodb-proxy
   - auth-service
   - mongodb-auth
   - auth-mailhog
   - accounting-service
   - postgres-accounting
   - flowise
   - flowise-postgres

---

## 🧪 Testing Endpoints

### From Windows Host:
```powershell
# Test Bridge UI
curl http://localhost:3082

# Test Flowise Proxy
curl http://localhost:8000/health

# Test Auth Service
curl http://localhost:3000/api/health

# Test Accounting Service
curl http://localhost:3001/api/health

# Test Flowise
curl http://localhost:3002/api/v1/ping
```

### From Inside Containers:
```bash
# Exec into flowise-proxy container
docker exec -it flowise-proxy sh

# Test container-to-container communication
wget -qO- http://auth-service:3000/api/health
wget -qO- http://accounting-service:3001/api/health
wget -qO- http://flowise:3000/api/v1/ping
```

---

## 🐛 Troubleshooting

### Bridge UI Can't Connect to API
**Problem:** Frontend shows connection errors
**Solution:** Check browser is using `http://localhost:8000` (not container name)
```yaml
# bridge/docker-compose.yml
- VITE_FLOWISE_PROXY_API_URL=http://host.docker.internal:8000
```

### Flowise Proxy Can't Reach Auth Service
**Problem:** `EXTERNAL_AUTH_URL` connection refused
**Solution:** Ensure both containers are on `chatproxy-network`
```bash
docker network inspect chatproxy-network
```

### Container Name Resolution Fails
**Problem:** `auth-service` hostname not found
**Solution:** Check container names match service names in docker-compose
```yaml
services:
  auth-service:
    container_name: auth-service  # Must match hostname used in URLs
```

---

## 📝 Summary

✅ **All endpoints are properly configured for Windows Docker deployment**

- Bridge UI (browser) → Flowise Proxy: Uses `host.docker.internal:8000`
- Container-to-Container: Uses Docker service names (e.g., `auth-service:3000`)
- File uploads: Handled inline in predict requests (Base64 encoding)
- All services connected via `chatproxy-network`
- Databases isolated in service-specific networks
