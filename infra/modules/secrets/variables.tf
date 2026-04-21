variable "project" {
  description = "Project name used in secret path prefix"
  type        = string
}

variable "env" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all secrets"
  type        = map(string)
  default     = {}
}
