# ================================================================
# Root Terraform Configuration — Prod Environment
# ================================================================
# Usage:
#   terraform init -backend-config=backend.hcl
#   terraform plan  -var-file=terraform.tfvars
#   terraform apply -var-file=terraform.tfvars
# ================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    # Values supplied via: terraform init -backend-config=backend.hcl
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "chatproxy"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "secrets" {
  source  = "../../modules/secrets"
  project = "chatproxy"
  env     = var.environment
}

module "flowise_aws" {
  source = "../../modules/flowise-aws"

  project             = "chatproxy"
  environment         = var.environment
  region              = var.aws_region
  domain_name         = var.domain_name
  hosted_zone_id      = var.hosted_zone_id
  certificate_arn     = var.certificate_arn
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs
  flowise_subdomain   = var.flowise_subdomain
  flowise_cpu         = var.flowise_cpu
  flowise_memory      = var.flowise_memory
  flowise_image       = var.flowise_image
  desired_count       = var.flowise_desired_count
  create_dns_records  = var.create_dns_records

  secret_flowise_config_arn = module.secrets.secret_flowise_config_arn
}

output "flowise_url" {
  value = module.flowise_aws.flowise_url
}

output "flowise_alb_dns_name" {
  value = module.flowise_aws.alb_dns_name
}

output "flowise_ecs_cluster_name" {
  value = module.flowise_aws.ecs_cluster_name
}

output "flowise_ecs_service_name" {
  value = module.flowise_aws.ecs_service_name
}

module "platform" {
  source = "../../modules/platform"

  project              = "chatproxy"
  environment          = var.environment
  vpc_cidr             = var.platform_vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.platform_public_subnet_cidrs
  private_subnet_cidrs = var.platform_private_subnet_cidrs
  domain_name          = var.domain_name
  hosted_zone_id       = var.hosted_zone_id
  certificate_arn      = var.certificate_arn
  create_dns_records   = var.create_dns_records
}

module "mongodb" {
  source = "../../modules/mongodb-ec2"

  project         = "chatproxy"
  environment     = var.environment
  vpc_id          = module.platform.vpc_id
  subnet_id       = module.platform.public_subnet_ids[0]
  ecs_tasks_sg_id = module.platform.ecs_tasks_sg_id

  depends_on = [module.secrets, module.platform]
}

module "auth_ecs" {
  source = "../../modules/auth-ecs"

  project                 = "chatproxy"
  environment             = var.environment
  region                  = var.aws_region
  vpc_id                  = module.platform.vpc_id
  subnet_ids              = module.platform.public_subnet_ids
  ecs_tasks_sg_id         = module.platform.ecs_tasks_sg_id
  https_listener_arn      = module.platform.https_listener_arn
  ecs_cluster_id          = module.platform.ecs_cluster_id
  cpu                     = var.auth_service_cpu
  memory                  = var.auth_service_memory
  image                   = var.auth_service_image
  domain_name             = var.domain_name
  ses_from_email          = var.ses_from_email
  secret_jwt_arn          = module.secrets.secret_jwt_arn
  secret_mongodb_auth_arn = module.secrets.secret_mongodb_auth_arn
  secret_ses_arn          = module.secrets.secret_ses_arn

  depends_on = [module.platform, module.mongodb]
}

output "platform_alb_dns_name" {
  value = module.platform.alb_dns_name
}

output "platform_ecs_cluster_name" {
  value = module.platform.ecs_cluster_name
}

output "mongodb_instance_id" {
  description = "Use with: aws ssm start-session --target <id>"
  value       = module.mongodb.instance_id
}

output "mongodb_private_ip" {
  value = module.mongodb.private_ip
}

output "auth_service_name" {
  value = module.auth_ecs.service_name
}

module "rds" {
  source = "../../modules/rds-postgres"

  project                  = "chatproxy"
  environment              = var.environment
  vpc_id                   = module.platform.vpc_id
  subnet_ids               = module.platform.private_subnet_ids
  ecs_tasks_sg_id          = module.platform.ecs_tasks_sg_id
  secret_db_accounting_arn = module.secrets.secret_db_accounting_arn
  db_name                  = var.db_name

  depends_on = [module.platform, module.secrets]
}

module "accounting_ecs" {
  source = "../../modules/accounting-ecs"

  project                  = "chatproxy"
  environment              = var.environment
  region                   = var.aws_region
  vpc_id                   = module.platform.vpc_id
  subnet_ids               = module.platform.public_subnet_ids
  ecs_tasks_sg_id          = module.platform.ecs_tasks_sg_id
  https_listener_arn       = module.platform.https_listener_arn
  ecs_cluster_id           = module.platform.ecs_cluster_id
  cpu                      = var.accounting_service_cpu
  memory                   = var.accounting_service_memory
  image                    = var.accounting_service_image
  domain_name              = var.domain_name
  db_host                  = module.rds.endpoint
  db_port                  = module.rds.port
  db_name                  = module.rds.db_name
  secret_db_accounting_arn = module.secrets.secret_db_accounting_arn
  secret_jwt_arn           = module.secrets.secret_jwt_arn

  depends_on = [module.platform, module.rds]
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint for accounting service"
  value       = module.rds.endpoint
}

output "accounting_service_name" {
  value = module.accounting_ecs.service_name
}

module "flowise_proxy_ecs" {
  source = "../../modules/flowise-proxy-ecs"

  project                    = "chatproxy"
  environment                = var.environment
  region                     = var.aws_region
  vpc_id                     = module.platform.vpc_id
  subnet_ids                 = module.platform.public_subnet_ids
  ecs_tasks_sg_id            = module.platform.ecs_tasks_sg_id
  https_listener_arn         = module.platform.https_listener_arn
  ecs_cluster_id             = module.platform.ecs_cluster_id
  cpu                        = var.flowise_proxy_cpu
  memory                     = var.flowise_proxy_memory
  image                      = var.flowise_proxy_service_image
  domain_name                = var.domain_name
  flowise_api_url            = "https://flowise.aidcec-ai-agent.com"
  secret_jwt_arn             = module.secrets.secret_jwt_arn
  secret_flowise_api_key_arn = module.secrets.secret_flowise_api_key_arn
  secret_mongodb_proxy_arn   = module.secrets.secret_mongodb_proxy_arn

  depends_on = [module.platform, module.mongodb, module.auth_ecs, module.accounting_ecs]
}

output "flowise_proxy_service_name" {
  value = module.flowise_proxy_ecs.service_name
}

module "bridge_ecs" {
  source = "../../modules/bridge-ecs"

  project            = "chatproxy"
  environment        = var.environment
  region             = var.aws_region
  vpc_id             = module.platform.vpc_id
  subnet_ids         = module.platform.public_subnet_ids
  ecs_tasks_sg_id    = module.platform.ecs_tasks_sg_id
  https_listener_arn = module.platform.https_listener_arn
  ecs_cluster_id     = module.platform.ecs_cluster_id
  cpu                = var.bridge_cpu
  memory             = var.bridge_memory
  image              = var.bridge_image

  depends_on = [module.platform]
}

output "bridge_service_name" {
  value = module.bridge_ecs.service_name
}

module "wireguard" {
  source = "../../modules/wireguard"

  project     = "chatproxy"
  environment = var.environment
  vpc_id      = module.platform.vpc_id
  subnet_id   = module.platform.public_subnet_ids[0]
  peers       = var.wireguard_peers

  depends_on = [module.platform]
}

output "wireguard_public_ip" {
  description = "WireGuard hub Elastic IP — use as Endpoint in workstation configs"
  value       = module.wireguard.public_ip
}

output "wireguard_instance_id" {
  description = "WireGuard EC2 instance ID (for SSM access)"
  value       = module.wireguard.instance_id
}