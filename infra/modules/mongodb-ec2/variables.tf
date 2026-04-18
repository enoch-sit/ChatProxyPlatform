variable "project" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to launch the instance in"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID (public subnet — needs internet for user data package install)"
  type        = string
}

variable "ecs_tasks_sg_id" {
  description = "Security group ID of ECS tasks (allowed to reach MongoDB on 27017)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (ARM64 / Graviton)"
  type        = string
  default     = "t4g.micro"
}
