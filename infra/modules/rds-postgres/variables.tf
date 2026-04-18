variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID for the RDS security group"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group (must be >= 2 AZs)"
  type        = list(string)
}

variable "ecs_tasks_sg_id" {
  description = "Security group ID of ECS tasks — allowed to reach port 5432"
  type        = string
}

variable "secret_db_accounting_arn" {
  description = "ARN of the Secrets Manager secret containing DB_USER and DB_PASSWORD"
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "accounting"
}
