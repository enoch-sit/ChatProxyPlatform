variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID (from platform module)"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for Fargate tasks"
  type        = list(string)
}

variable "ecs_tasks_sg_id" {
  description = "Security group ID for ECS tasks (from platform module)"
  type        = string
}

variable "https_listener_arn" {
  description = "ARN of the HTTPS:443 ALB listener (from platform module)"
  type        = string
}

variable "ecs_cluster_id" {
  description = "ECS cluster ARN (from platform module)"
  type        = string
}

variable "cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of auth service tasks to run"
  type        = number
  default     = 1
}

variable "image" {
  description = "ECR image URI for the auth service (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/chatproxy/auth-service:latest)"
  type        = string
}

variable "domain_name" {
  description = "Apex domain name — used for CORS_ORIGIN and FRONTEND_URL"
  type        = string
}

variable "ses_from_email" {
  description = "FROM address for SES email (EMAIL_FROM env var)"
  type        = string
}

variable "secret_jwt_arn" {
  description = "ARN of /chatproxy/ENV/jwt secret (JWT_ACCESS_SECRET + JWT_REFRESH_SECRET)"
  type        = string
}

variable "secret_mongodb_auth_arn" {
  description = "ARN of /chatproxy/ENV/mongodb/auth secret (MONGODB_URI)"
  type        = string
}

variable "secret_ses_arn" {
  description = "ARN of /chatproxy/ENV/ses secret (SMTP_USER + SMTP_PASS)"
  type        = string
}
