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
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "image" {
  description = "ECR image URI for the flowise-proxy service"
  type        = string
}

variable "domain_name" {
  type = string
}

variable "flowise_api_url" {
  description = "URL of the Flowise instance (ALB or direct)"
  type        = string
}

variable "secret_jwt_arn" {
  description = "ARN of the jwt secret (JWT_ACCESS_SECRET + JWT_REFRESH_SECRET)"
  type        = string
}

variable "secret_flowise_api_key_arn" {
  description = "ARN of the flowise/api-key secret"
  type        = string
}

variable "secret_mongodb_proxy_arn" {
  description = "ARN of the mongodb/proxy secret (MONGODB_URL)"
  type        = string
}
