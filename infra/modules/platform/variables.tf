variable "project" {
  description = "Project name prefix (e.g. chatproxy)"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC (must not overlap with flowise VPC 10.0.0.0/16)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs (must have at least 2)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets — one per AZ (ALB + Fargate tasks)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets — one per AZ (MongoDB EC2, RDS)"
  type        = list(string)
  default     = ["10.1.11.0/24", "10.1.12.0/24"]
}

variable "domain_name" {
  description = "Apex domain name (e.g. aidcec-ai-agent.com)"
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN covering apex + wildcard"
  type        = string
}

variable "create_dns_records" {
  description = "Whether to create the Route53 apex record. Set to false in environments that share a hosted zone with another active environment to avoid collisions."
  type        = bool
  default     = true
}
