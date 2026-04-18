---
description: "Onboard a new Windows workstation to the WireGuard fleet"
mode: agent
tools:
  - run_in_terminal
  - read_file
  - replace_string_in_file
---

# Onboard New Workstation

You are helping onboard a new Windows workstation into the ChatProxy fleet managed by WireGuard VPN.

## Context Files
- `fleet-inventory.json` — workstation registry (read first)
- `fleet.ps1` — fleet management script
- `wg-workstation-setup.ps1` — WireGuard client setup for the new machine
- `infra/environments/dev/terraform.tfvars` — Terraform peer list

## Steps

1. **Ask for details**: workstation name, WireGuard IP (next available in 10.10.0.0/24), SSH user, role, services
2. **Add to fleet-inventory.json**: Add a new entry to the `workstations` array
3. **Add to terraform.tfvars**: Add a new peer to the `wireguard_peers` list (needs the workstation's WireGuard public key)
4. **Generate the setup command** the user should run on the new workstation:
   ```powershell
   .\wg-workstation-setup.ps1 -HubEndpoint "3.220.226.162:51820" -HubPublicKey "<server_public_key>" -MyIP "10.10.0.X/24"
   ```
5. **Remind**: After the workstation generates its keys, the public key must be added as a peer on the hub via SSM:
   ```bash
   aws ssm send-command --instance-ids i-021b5be52f91cc6fa --document-name AWS-RunShellScript \
     --parameters 'commands=["wg set wg0 peer <NEW_PUBLIC_KEY> allowed-ips 10.10.0.X/32 persistent-keepalive 25","wg-quick save wg0"]'
   ```
6. **Deploy SSH key**: Run `.\fleet.ps1 -Action deploy-key` and install the public key on the new workstation
7. **Verify**: Run `.\fleet.ps1 -Action status -Target <name>` to confirm connectivity

## Important
- WireGuard hub EIP: 3.220.226.162
- Hub instance: i-021b5be52f91cc6fa
- Server public key: cUDvoyHcJs7T3mpfQYA0xJ130/ff4udsNBchH+/l7T0=
- Network: 10.10.0.0/24 (hub is .1)
- Never expose private keys in chat — only exchange public keys
