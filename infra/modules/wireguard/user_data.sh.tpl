#!/bin/bash
set -euo pipefail

# ================================================================
# WireGuard Hub — User Data (Amazon Linux 2023 ARM64)
#
# Installs WireGuard, generates server keys, configures interface,
# and adds pre-defined peers.
# ================================================================

exec > >(tee /var/log/wireguard-setup.log) 2>&1
echo "=== WireGuard setup starting at $(date) ==="

# ── Install WireGuard ─────────────────────────────────────────────────
dnf install -y wireguard-tools

# ── Generate server keys ─────────────────────────────────────────────
umask 077
mkdir -p /etc/wireguard

wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key

SERVER_PRIVKEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUBKEY=$(cat /etc/wireguard/server_public.key)

# ── Write WireGuard config ───────────────────────────────────────────
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = ${wg_server_ip}
ListenPort = ${wg_listen_port}
PrivateKey = $SERVER_PRIVKEY

# Enable IP forwarding for hub-and-spoke routing
PostUp   = sysctl -w net.ipv4.ip_forward=1; iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT

%{ for peer in peers ~}
# Peer: ${peer.name}
[Peer]
PublicKey = ${peer.public_key}
AllowedIPs = ${peer.allowed_ip}
%{ endfor ~}
EOF

chmod 600 /etc/wireguard/wg0.conf

# ── Enable and start WireGuard ───────────────────────────────────────
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# ── Write server public key for easy retrieval via SSM ───────────────
echo "$SERVER_PUBKEY" > /etc/wireguard/server_public.key
echo "Server public key: $SERVER_PUBKEY"

echo "=== WireGuard setup complete at $(date) ==="
