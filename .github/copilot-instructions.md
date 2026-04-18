# ChatProxy Platform — Copilot Instructions

## Project Overview
Multi-service chat proxy platform with WireGuard-based fleet management for Windows workstations.

## Architecture
- **Services**: auth-service (Node 18), accounting-service (Node 18), flowise-proxy (Python 3.11/FastAPI), bridge (React/Vite), flowise (FlowiseAI)
- **Fleet**: Windows workstations connected via WireGuard VPN through an AWS hub (EC2 t4g.nano)
- **Cloud**: AWS ECS Fargate (us-east-1), ECR, ALB, Route53, ACM
- **IaC**: Terraform under `infra/`

## Key Files at Root
| File | Purpose |
|------|---------|
| `fleet.ps1` | Central fleet management (status, patch, health, setup, deploy-key, run-command) |
| `setup.ps1` | One-command workstation setup |
| `patch.ps1` | Pull updates & redeploy changed services |
| `diagnose.ps1` | Diagnostics & health checks |
| `wg-workstation-setup.ps1` | WireGuard + OpenSSH onboarding for new workstations |
| `fleet-inventory.json` | Workstation registry (names, IPs, roles) |
| `workstation-manifest.json` | Service deploy order & metadata |
| `version.json` | Service version tracking |

## Conventions
- PowerShell scripts use `$PSScriptRoot` for paths — keep fleet.ps1 and its dependencies co-located at root
- Fleet scripts SSH via WireGuard tunnel (10.10.0.0/24), not public IPs
- Never expose private keys or secrets in code/chat — only public keys
- Terraform peers are managed via SSM (not terraform apply) due to `ignore_changes` lifecycle
- Utility scripts live in `scripts/`, docs in `docs/`, logs in `logs/`

## Fleet Management
- Hub: 10.10.0.1 (EIP 3.220.226.162, instance i-021b5be52f91cc6fa)
- SSH key: `~/.ssh/fleet_ed25519`
- All fleet actions go through `fleet.ps1` which SSHs to workstations and runs the appropriate ps1 script
