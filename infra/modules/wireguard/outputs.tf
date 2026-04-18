output "public_ip" {
  value       = aws_eip.wireguard.public_ip
  description = "Elastic IP of the WireGuard hub — use this as the Endpoint in workstation configs"
}

output "instance_id" {
  value       = aws_instance.wireguard.id
  description = "EC2 instance ID (for SSM access)"
}

output "security_group_id" {
  value       = aws_security_group.wireguard.id
  description = "Security group ID"
}

output "vpn_subnet" {
  value       = var.wg_subnet
  description = "VPN subnet CIDR"
}
