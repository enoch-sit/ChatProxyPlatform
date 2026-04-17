---
description: "Manage WireGuard VPN infrastructure — hub, peers, tunnels"
mode: agent
tools:
  - run_in_terminal
  - read_file
  - replace_string_in_file
---

# WireGuard Infrastructure

You are helping manage the WireGuard VPN infrastructure that connects the ChatProxy fleet.

## Architecture
- **Hub**: AWS EC2 t4g.nano running WireGuard (Amazon Linux 2023)
  - Instance: `i-021b5be52f91cc6fa`
  - EIP: `3.220.226.162`
  - WireGuard IP: `10.10.0.1`
  - UDP Port: `51820`
  - Server Public Key: `cUDvoyHcJs7T3mpfQYA0xJ130/ff4udsNBchH+/l7T0=`
- **Network**: `10.10.0.0/24`
- **Terraform**: `infra/modules/wireguard/` (module), `infra/environments/dev/` (config)

## Common Tasks

### Check hub status
```bash
aws ssm send-command --instance-ids i-021b5be52f91cc6fa \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["wg show","ip addr show wg0"]' \
  --region us-east-1
```

### Add a new peer (live, without Terraform)
```bash
aws ssm send-command --instance-ids i-021b5be52f91cc6fa \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["wg set wg0 peer <PUBLIC_KEY> allowed-ips 10.10.0.X/32 persistent-keepalive 25","wg-quick save wg0"]' \
  --region us-east-1
```
Also add to `infra/environments/dev/terraform.tfvars` under `wireguard_peers` for persistence.

### Remove a peer
```bash
aws ssm send-command --instance-ids i-021b5be52f91cc6fa \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["wg set wg0 peer <PUBLIC_KEY> remove","wg-quick save wg0"]' \
  --region us-east-1
```

### Workstation-side setup
```powershell
.\wg-workstation-setup.ps1 -HubEndpoint "3.220.226.162:51820" -HubPublicKey "cUDvoyHcJs7T3mpfQYA0xJ130/ff4udsNBchH+/l7T0=" -MyIP "10.10.0.X/24"
```

## Important Notes
- Terraform has `lifecycle { ignore_changes = [ami, user_data] }` — peer changes must go through SSM, not terraform apply
- Always `wg-quick save wg0` after `wg set` to persist across reboots
- Security group only allows UDP 51820 inbound; SSH is restricted to the VPN subnet
- Never share private keys — only exchange public keys
