# CI-specific tfvars for GitHub Actions deploy pipeline.
# Contains only non-sensitive infrastructure configuration.
# All secrets/credentials are in AWS Secrets Manager, not here.
# Image URIs in this file are overridden per-deploy by the CI -var flag.

aws_account_id = "168437900315"
environment    = "dev"

domain_name        = "aidcec-ai-agent.com"
hosted_zone_id     = "Z044412126W7PYEQ37Z7Q"
certificate_arn    = "arn:aws:acm:us-east-1:168437900315:certificate/b0db5ad5-1243-4a3e-a2d5-7baaa193c649"

vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]

platform_public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
platform_private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]

ses_from_email              = "noreply@aidcec-ai-agent.com"
service_discovery_namespace = "chatproxy.dev.local"

auth_service_cpu          = 256
auth_service_memory       = 512
accounting_service_cpu    = 256
accounting_service_memory = 512
flowise_proxy_cpu         = 512
flowise_proxy_memory      = 1024
bridge_cpu                = 256
bridge_memory             = 512
flowise_image             = "flowiseai/flowise:3.0.0"

# Image URIs below are used as fallbacks; CI overrides the targeted service image via -var.
auth_service_image          = "168437900315.dkr.ecr.us-east-1.amazonaws.com/chatproxy/auth-service:debug-batch-f7d02e9"
accounting_service_image    = "168437900315.dkr.ecr.us-east-1.amazonaws.com/chatproxy/accounting-service:latest"
flowise_proxy_service_image = "168437900315.dkr.ecr.us-east-1.amazonaws.com/chatproxy/flowise-proxy:v1.0.0-acdbc6f"
bridge_image                = "168437900315.dkr.ecr.us-east-1.amazonaws.com/chatproxy/bridge:v1.0.0-1620e77"

wireguard_peers = [
  {
    name       = "aidcec-demo-windows-workstation"
    public_key = "leZtpHFhPMLf0F2Q28a7nxoIPlx/nGb2d5AZp+b4hgM="
    allowed_ip = "10.10.0.2/32"
  }
]
