variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the domain"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN (must cover domain + wildcard)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "auth_service_cpu" {
  type    = number
  default = 256
}

variable "auth_service_memory" {
  type    = number
  default = 512
}

variable "accounting_service_cpu" {
  type    = number
  default = 256
}

variable "accounting_service_memory" {
  type    = number
  default = 512
}

variable "flowise_proxy_cpu" {
  type    = number
  default = 512
}

variable "flowise_proxy_memory" {
  type    = number
  default = 1024
}

variable "bridge_cpu" {
  type    = number
  default = 256
}

variable "bridge_memory" {
  type    = number
  default = 512
}

variable "flowise_cpu" {
  type    = number
  default = 512
}

variable "flowise_memory" {
  type    = number
  default = 1024
}

variable "flowise_subdomain" {
  description = "Subdomain used for the standalone Flowise endpoint"
  type        = string
  default     = "flowise"
}

variable "flowise_image" {
  description = "Container image for Flowise service"
  type        = string
  default     = "flowiseai/flowise:latest"
}

variable "flowise_desired_count" {
  description = "Desired number of Flowise tasks"
  type        = number
  default     = 1
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "accounting"
}

variable "db_master_username" {
  description = "RDS master username"
  type        = string
  default     = "chatproxy_admin"
}

variable "ses_from_email" {
  description = "FROM address for SES email sending"
  type        = string
}

variable "service_discovery_namespace" {
  description = "AWS Cloud Map namespace for ECS service discovery"
  type        = string
  default     = "chatproxy.dev.local"
}

# ── Platform VPC (separate CIDR from flowise VPC 10.0.x.x) ───────────

variable "platform_public_subnet_cidrs" {
  description = "Public subnet CIDRs for the platform VPC (ALB + Fargate tasks)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "platform_private_subnet_cidrs" {
  description = "Private subnet CIDRs for the platform VPC (MongoDB EC2, RDS)"
  type        = list(string)
  default     = ["10.1.11.0/24", "10.1.12.0/24"]
}

# ── Auth Service ───────────────────────────────────────────────────────

variable "auth_service_image" {
  description = "ECR image URI for the auth service"
  type        = string
}

variable "accounting_service_image" {
  description = "ECR image URI for the accounting service"
  type        = string
}

variable "flowise_proxy_service_image" {
  description = "ECR image URI for the flowise-proxy service"
  type        = string
}

variable "bridge_image" {
  description = "ECR image URI for the bridge frontend"
  type        = string
}

