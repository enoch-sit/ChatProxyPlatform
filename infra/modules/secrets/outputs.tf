output "secret_jwt_arn" {
  description = "ARN of the JWT secrets (JWT_ACCESS_SECRET + JWT_REFRESH_SECRET)"
  value       = aws_secretsmanager_secret.secrets["jwt"].arn
}

output "secret_db_accounting_arn" {
  description = "ARN of the accounting-service PostgreSQL credentials"
  value       = aws_secretsmanager_secret.secrets["db/accounting"].arn
}

output "secret_db_flowise_arn" {
  description = "ARN of the Flowise PostgreSQL credentials"
  value       = aws_secretsmanager_secret.secrets["db/flowise"].arn
}

output "secret_mongodb_auth_arn" {
  description = "ARN of the auth-service MongoDB URI"
  value       = aws_secretsmanager_secret.secrets["mongodb/auth"].arn
}

output "secret_mongodb_proxy_arn" {
  description = "ARN of the flowise-proxy MongoDB URL"
  value       = aws_secretsmanager_secret.secrets["mongodb/proxy"].arn
}

output "secret_flowise_api_key_arn" {
  description = "ARN of the Flowise API key used by flowise-proxy"
  value       = aws_secretsmanager_secret.secrets["flowise/api-key"].arn
}

output "secret_flowise_config_arn" {
  description = "ARN of Flowise runtime config (secret key overwrite, auth credentials)"
  value       = aws_secretsmanager_secret.secrets["flowise/config"].arn
}

output "secret_ses_arn" {
  description = "ARN of the SES SMTP credentials for auth-service"
  value       = aws_secretsmanager_secret.secrets["ses"].arn
}

output "all_secret_arns" {
  description = "Map of secret key → ARN (useful for IAM policy construction)"
  value       = { for k, v in aws_secretsmanager_secret.secrets : k => v.arn }
}
