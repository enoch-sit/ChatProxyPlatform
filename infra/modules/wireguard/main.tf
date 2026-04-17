# ================================================================
# WireGuard VPN Hub — EC2 Module
#
# Deploys a t4g.nano EC2 instance (Amazon Linux 2023 ARM64) as a
# WireGuard VPN hub for fleet management of Windows workstations.
#
# Features:
#   - WireGuard VPN server with auto-configured peers
#   - SSH relay to reach workstations behind NAT
#   - Elastic IP for stable endpoint
#   - SSM Session Manager for admin access (no bastion needed)
#   - Minimal cost: ~$3-5/month
#
# Workstation peers are configured via the `peers` variable.
# Each peer gets a 10.10.0.x address on the VPN.
# ================================================================

locals {
  name_prefix = "${var.project}-${var.environment}-wireguard"
}

# ── WireGuard server private key (stored in Terraform state) ─────────

resource "random_id" "wg_key_seed" {
  byte_length = 32
}

# ── Security Group ────────────────────────────────────────────────────

resource "aws_security_group" "wireguard" {
  name        = "${local.name_prefix}-sg"
  description = "WireGuard VPN hub"
  vpc_id      = var.vpc_id

  # WireGuard UDP
  ingress {
    from_port   = var.wg_listen_port
    to_port     = var.wg_listen_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "WireGuard from anywhere"
  }

  # SSH from VPN subnet only (for fleet management relay)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.wg_subnet]
    description = "SSH from VPN peers only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg" }
}

# ── IAM Role (SSM access) ────────────────────────────────────────────

resource "aws_iam_role" "wireguard" {
  name = "${local.name_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.wireguard.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "wireguard" {
  name = "${local.name_prefix}-profile"
  role = aws_iam_role.wireguard.name
}

# ── Latest Amazon Linux 2023 ARM64 AMI ───────────────────────────────

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── EC2 Instance ──────────────────────────────────────────────────────

resource "aws_instance" "wireguard" {
  ami                         = data.aws_ami.al2023_arm.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.wireguard.id]
  iam_instance_profile        = aws_iam_instance_profile.wireguard.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    wg_listen_port = var.wg_listen_port
    wg_subnet      = var.wg_subnet
    wg_server_ip   = var.wg_server_ip
    peers          = var.peers
  })

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = { Name = local.name_prefix }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ── Elastic IP (stable endpoint for workstations) ────────────────────

resource "aws_eip" "wireguard" {
  instance = aws_instance.wireguard.id
  domain   = "vpc"

  tags = { Name = "${local.name_prefix}-eip" }
}
