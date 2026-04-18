variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "hosted_zone_id" {
  type = string
}

variable "certificate_arn" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "flowise_subdomain" {
  type    = string
  default = "flowise"
}

variable "flowise_cpu" {
  type    = number
  default = 512
}

variable "flowise_memory" {
  type    = number
  default = 1024
}

variable "flowise_image" {
  type    = string
  default = "flowiseai/flowise:latest"
}

variable "desired_count" {
  type    = number
  default = 1
}
