# ChatProxy Platform

> A complete AI chatbot platform with user management, credit tracking, and enterprise-grade authentication

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://www.docker.com/)
[![Platform](https://img.shields.io/badge/platform-windows-lightgrey.svg)](https://www.microsoft.com/windows)

---

## 🚀 Quick Start

There are **3 scripts** that handle everything on a workstation:

| Script | Purpose |
|--------|---------|
| `.\setup.ps1` | Fresh machine setup (prereqs, secrets, .env, start services) |
| `.\patch.ps1` | Pull updates & redeploy changed services |
| `.\diagnose.ps1` | Health checks, troubleshooting, diagnostics |

**First-time setup:**
```powershell
# 1. Clone the repo and run the setup script
.\setup.ps1

# 2. Access the platform
# http://localhost:3082 (Bridge UI)
# http://localhost:3002 (Flowise Admin)
```

**Pull latest changes:**
```powershell
.\patch.ps1                          # Auto-detect what changed, rebuild as needed
.\patch.ps1 -Mode full              # Force full rebuild of changed services
.\patch.ps1 -Service auth-service   # Patch a single service
.\patch.ps1 -Mode status            # Check version & what's pending
```

**Troubleshooting:**
```powershell
.\diagnose.ps1                      # Full diagnostic report
.\diagnose.ps1 -Quick               # Quick health check
.\diagnose.ps1 -Login               # Login problem diagnostics
```

### AWS Deployment (infra/scripts/)

```powershell
# Bump service version
.\infra\scripts\bump-version.ps1 -Service auth-service -Type patch

# Deploy to AWS ECS (auto-tags from version.json)
.\infra\scripts\deploy-service.ps1 -Service auth-service

# Deploy with auto-rollback
.\infra\scripts\deploy-service.ps1 -Service auth-service -AutoRollback

# Dry run
.\infra\scripts\deploy-service.ps1 -Service bridge -DryRun
```

---

## 📚 Documentation

### Getting Started
- **[DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md)** - Complete installation guide for beginners (START HERE)
- **[DEPLOYMENT_AND_PATCHING_PLAN.md](DEPLOYMENT_AND_PATCHING_PLAN.md)** - Versioning, CI/CD, and fleet management plan
- **[SETUP_GUIDE.md](SETUP_GUIDE.md)** - Service-specific setup instructions

### Operations Scripts
| Script | Description |
|--------|-------------|
| `setup.ps1` | One-command workstation setup |
| `patch.ps1` | Pull & deploy updates with change detection |
| `diagnose.ps1` | Full diagnostic suite |
| `infra/scripts/bump-version.ps1` | Semver bumping + git tags |
| `infra/scripts/deploy-service.ps1` | AWS ECR → Terraform → ECS deploy pipeline |

### Configuration
| File | Purpose |
|------|---------|
| `version.json` | Service versions — single source of truth |
| `workstation-manifest.json` | Fleet metadata: deploy order, ports, tools |
| `.local-version` | Tracks what's deployed on this machine |

### Technical Documentation
- **[docs/SERVICE_ARCHITECTURE.md](docs/SERVICE_ARCHITECTURE.md)** - System architecture overview
- **[docs/JWT_AUTHENTICATION_FIXES.md](docs/JWT_AUTHENTICATION_FIXES.md)** - Authentication implementation details

### CI/CD (GitHub Actions)
| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Pull request / push | Lint, test, typecheck, Docker build per changed service |
| `deploy-dev.yml` | Push to main | Build → ECR push → Terraform apply → ECS wait stable |
| `rollback.yml` | Manual dispatch | Revert a service to a previous ECS task definition |

### Fleet Management (WireGuard VPN)

Centrally manage multiple Windows workstations over a WireGuard VPN tunnel.

| File | Purpose |
|------|---------|
| `fleet.ps1` | Central management: status, patch, health, setup, deploy-key, run-command |
| `wg-workstation-setup.ps1` | Configure WireGuard + OpenSSH on a new workstation |
| `fleet-inventory.json` | Registry of hub + workstation IPs, SSH users, roles |
| `infra/modules/wireguard/` | Terraform module for the AWS VPN hub (~$5/mo) |

**Quick start:**
```powershell
# 1. Deploy the hub
terraform -chdir=infra/environments/dev apply -var-file=terraform.tfvars

# 2. On each workstation, run:
.\wg-workstation-setup.ps1 -HubEndpoint "<EIP>:51820" -HubPublicKey "<key>" -MyIP "10.10.0.X/24"

# 3. From your management machine:
.\fleet.ps1 -Action status          # Check all workstations
.\fleet.ps1 -Action patch           # Patch all workstations
.\fleet.ps1 -Action health          # Run diagnostics everywhere
```

---

## 🎯 Features

### For End Users
- 🤖 **AI Chat Interface** - Interact with custom AI chatflows
- 👥 **Multi-User Support** - Teachers and students with role-based access
- 💳 **Credit System** - Track and manage AI usage credits
- 📱 **Modern UI** - Clean, responsive web interface
- 🔐 **Secure Authentication** - JWT-based login with auto-refresh

### For Administrators
- 📊 **User Management** - CSV-based system (no coding required)
- 🔧 **Chatflow Builder** - Visual AI flow designer (Flowise)
- 📈 **Credit Allocation** - Flexible credit management per user
- 🛡️ **Role-Based Access** - Admin, teacher, and student roles
- 📋 **Usage Tracking** - Monitor AI usage and costs

### For Developers
- 🐳 **Docker-Ready** - All services containerized
- 🔌 **Microservices** - Modular architecture
- 🗄️ **Multiple Databases** - MongoDB + PostgreSQL
- 🔑 **JWT Authentication** - Secure token-based auth
- 📝 **Complete API** - RESTful endpoints for all services

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Interface                          │
│  Bridge UI (React + TypeScript) - Port 3082                 │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│              Integration Layer                              │
│  Flowise Proxy (Python FastAPI) - Port 8000                 │
└───────┬─────────────────┬─────────────────┬─────────────────┘
        │                 │                 │
        ▼                 ▼                 ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│ Auth Service  │ │  Accounting   │ │    Flowise    │
│  (Node.js)    │ │   Service     │ │   (Node.js)   │
│  Port: 3000   │ │  (Node.js)    │ │   Port: 3002  │
│               │ │  Port: 3001   │ │               │
│  MongoDB      │ │  PostgreSQL   │ │  PostgreSQL   │
└───────────────┘ └───────────────┘ └───────────────┘
```

**Services:**
- **Bridge UI** - User-facing web application
- **Flowise Proxy** - API gateway and service orchestration
- **Auth Service** - User authentication and authorization
- **Accounting Service** - Credit management and usage tracking
- **Flowise** - AI chatflow builder and execution engine

---

## 📋 Prerequisites

- **Windows 10/11** (with administrator access)
- **Docker Desktop** - Container platform
- **Python 3.x** - Required for setup scripts
- **Git** - Optional but recommended
- **8+ GB RAM** - Recommended
- **20+ GB Disk Space** - For Docker images and databases

**Quick Check:**
```bash
check_system.bat
```

---

## 🎓 User Management

### Simple CSV-Based System

**No coding required!** Manage users through a simple spreadsheet.

**Location:** `auth-service\quickCreateAdminPy\users.csv`

**Example:**
```csv
action,username,email,password,role,fullName,credits
create,teacher1,teacher1@school.com,Teacher1!,teacher,John Doe,5000
create,student1,student1@school.com,Student1!,student,Jane Smith,1000
delete,olduser,old@school.com,,,0
```

**To Update:**
1. Edit `users.csv` in Excel or Notepad
2. Run `sync_all_users.bat`
3. Done!

**Actions:**
- `create` - Add new user
- `delete` - Remove user

**Roles:**
- `teacher` - Higher credits (default: 5000)
- `student` - Standard credits (default: 1000)
- `admin` - Full access (unlimited credits)

---

## 🔐 Default Credentials

### Bridge UI (User Login)
- **Admin:** admin / admin@admin
- **Teachers/Students:** Defined in users.csv

### Flowise (Admin Panel)
- **Email:** ecysit@eduhk.hk
- **Password:** Admin@2026

⚠️ **IMPORTANT:** Change these before production use!

---

## 🌐 Service URLs

| Service | URL | Description |
|---------|-----|-------------|
| **Bridge UI** | http://localhost:3082 | Main user interface |
| **Flowise** | http://localhost:3002 | AI flow builder (admin) |
| **Auth API** | http://localhost:3000 | Authentication service |
| **Accounting API** | http://localhost:3001 | Credit management |
| **Flowise Proxy** | http://localhost:8000 | Integration API |
| **MailHog** | http://localhost:8025 | Email testing (dev) |

---

## 🛠️ Common Tasks

### Start All Services
```powershell
.\setup.ps1 -SkipPrereqs     # Start everything (skip install checks)
```

### Stop All Services
```powershell
.\infra\scripts\dev-stop.ps1  # Stop all Docker Compose services
```

### Check System Health
```powershell
.\diagnose.ps1 -Quick         # Quick container + endpoint check
.\diagnose.ps1                 # Full diagnostic
```

### Pull Updates & Rebuild
```powershell
.\patch.ps1                    # Auto-detect changes and deploy
.\patch.ps1 -Mode full        # Force full rebuild
.\patch.ps1 -Mode status      # See what's pending
```

### Add/Update Users
```bash
cd auth-service\quickCreateAdminPy
notepad users.csv                # Edit users
sync_all_users.bat               # Apply changes
```

### View Service Logs
```bash
docker logs flowise -f
docker logs auth-service -f
docker logs flowise-proxy -f
docker logs accounting-service -f
docker logs bridge-ui -f
```

### Backup Data
```bash
# Manual backup
docker exec mongodb-auth mongodump --out /backup
docker exec postgres-accounting pg_dump > backup.sql
docker exec flowise-postgres pg_dump > flowise_backup.sql

# Automated (if implemented)
backup_databases.bat
```

---

## 🐛 Troubleshooting

### Quick Diagnostics
```powershell
.\diagnose.ps1 -Quick          # Container + endpoint health
.\diagnose.ps1 -Login          # Login-specific diagnostics
.\diagnose.ps1 -Users          # List users from MongoDB
```

### Services Won't Start
```powershell
# Check Docker is running
docker --version
docker ps

# Full diagnostic
.\diagnose.ps1
```

### Common Issues

| Problem | Solution |
|---------|----------|
| Port already in use | Stop conflicting service or restart computer |
| Docker not running | Start Docker Desktop, wait for green icon |
| Login fails | Run `sync_all_users.bat` to re-sync users |
| Chatflows not visible | Check Flowise API key in flowise-proxy-service-py/.env |
| Credits not tracking | Restart accounting-service |
| Out of disk space | Run `docker system prune -a` |

### Get Detailed Diagnostics
```powershell
.\diagnose.ps1 -SaveLog
# Creates detailed report in logs/diagnose_[date].log
```

---

## 🧪 Testing

### Quick Test
```bash
# 1. Login to Bridge UI
# http://localhost:3082
# Username: admin / Password: admin@admin

# 2. Select a chatflow

# 3. Send a test message

# 4. Verify:
# - AI responds
# - Credits decrease
# - Chat history saved
```

### Authentication Testing
See [docs/JWT_TESTING_PLAN.md](docs/JWT_TESTING_PLAN.md) for comprehensive JWT testing procedures.

---

## 📦 Project Structure

```
ChatProxy Platform/
├── setup.ps1                       ← One-command workstation setup
├── patch.ps1                       ← Pull updates & redeploy
├── diagnose.ps1                    ← Diagnostics & health checks
├── version.json                    ← Service version registry
├── workstation-manifest.json       ← Fleet metadata & deploy order
├── .local-version                  ← This machine's deployed version
│
├── .github/workflows/              ← CI/CD pipelines
│   ├── ci.yml                      ← PR checks (lint, test, build)
│   ├── deploy-dev.yml              ← Auto-deploy on push to main
│   └── rollback.yml                ← Manual rollback trigger
│
├── infra/                          ← Terraform + deploy scripts
│   ├── scripts/
│   │   ├── deploy-service.ps1      ← AWS ECR → ECS deploy pipeline
│   │   └── bump-version.ps1        ← Semver bumping + git tags
│   ├── environments/dev/           ← Dev environment config
│   └── modules/                    ← Terraform modules
│
├── bridge/                         ← Frontend (React + TypeScript)
├── flowise/                        ← AI Flow Builder
├── flowise-proxy-service-py/       ← Integration Layer (Python)
├── auth-service/                   ← Authentication (Node.js)
├── accounting-service/             ← Credit Management (Node.js)
│
├── docs/                           ← Technical documentation
└── scripts/archive/                ← Legacy .bat scripts (kept for reference)
```

---

## 🔒 Security

### For Development
- Default credentials provided for quick setup
- HTTP connections (localhost only)
- Self-signed certificates accepted

### For Production
**Before deploying to production, you MUST:**

1. **Change all default passwords**
   - Admin accounts
   - Database passwords
   - JWT secrets

2. **Enable HTTPS**
   - Install valid SSL certificates
   - Configure nginx for SSL
   - Update all service URLs

3. **Secure database access**
   - Change MongoDB root password
   - Change PostgreSQL passwords
   - Restrict network access

4. **Update JWT secrets**
   - Generate new secrets: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
   - Update in auth-service/.env
   - Update in flowise-proxy-service-py/.env

5. **Configure CORS properly**
   - Restrict origins to your domain
   - Remove localhost from allowed origins

6. **Set up backups**
   - Daily database backups
   - Off-site backup storage
   - Test recovery procedures

7. **Enable logging and monitoring**
   - Centralized log collection
   - Error tracking
   - Performance monitoring

---

## 🤝 Contributing

Contributions are welcome! This is an open-source project.

### How to Contribute
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Setup
See [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md) for complete setup instructions.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Copyright © 2026 Enoch Sit**

Permission is granted to use, copy, modify, and distribute this software for any purpose with or without fee.

---

## 🙏 Acknowledgments

- **Flowise** - AI flow builder framework
- **Docker** - Container platform
- **React** - UI framework
- **FastAPI** - Python web framework
- **Node.js** - Backend runtime
- **MongoDB** - Document database
- **PostgreSQL** - Relational database

---

## 📞 Support

### Documentation
- **Installation:** [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md)
- **User Management:** [SETUP_GUIDE.md](SETUP_GUIDE.md)
- **Architecture:** [docs/SERVICE_ARCHITECTURE.md](docs/SERVICE_ARCHITECTURE.md)
- **Troubleshooting:** Run `check_system.bat`

### Common Resources
- Docker Desktop: https://www.docker.com/products/docker-desktop
- Python: https://www.python.org/downloads/
- Git: https://git-scm.com/download/win

### System Check
```bash
check_system.bat
```
Generates a detailed diagnostic report to help identify issues.

---

## 📊 Status

**Current Version:** 1.0.0  
**Status:** ✅ Production Ready (after security hardening)  
**Last Updated:** February 11, 2026

**System Health:**
- ✅ All services operational
- ✅ Authentication working (JWT with 1-hour tokens)
- ✅ User management functional
- ✅ Credit tracking active
- ✅ AI chatflows deployed

**Recent Updates:**
- JWT token lifetime increased to 1 hour
- Background token refresh improved
- Server-side logout implemented
- Complete documentation reorganized
- MIT License added

---

## 🎯 Roadmap

### Planned Features
- [ ] Automated backup system
- [ ] SSL/HTTPS support via nginx
- [ ] Advanced user analytics
- [ ] Email notifications
- [ ] Mobile-responsive improvements
- [ ] Multi-language support
- [ ] API rate limiting
- [ ] Advanced chatflow templates

### In Progress
- [x] Documentation reorganization
- [x] MIT License
- [x] System health checker
- [x] JWT authentication improvements

---

**Made with ❤️ by Enoch Sit**

*Thank God for Jesus Christ - The source of all wisdom and creativity*
