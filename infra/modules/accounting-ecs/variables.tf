variable "project"     { type = string }
variable "environment" { type = string }
variable "region"      { type = string }

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "ecs_tasks_sg_id" {
  type = string
}

variable "https_listener_arn" {
  type = string
}

variable "ecs_cluster_id" {
  type = string
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "image" {
  description = "ECR image URI for the accounting service"
  type        = string
}

variable "domain_name" {
  type = string
}

variable "db_host" {
  description = "RDS endpoint hostname (from rds-postgres module output)"
  type        = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type    = string
  default = "accounting"
}

variable "secret_db_accounting_arn" {
  description = "Secrets Manager ARN containing DB_USER and DB_PASSWORD"
  type        = string
}

variable "secret_jwt_arn" {
  description = "Secrets Manager ARN containing JWT_ACCESS_SECRET"
  type        = string
}
