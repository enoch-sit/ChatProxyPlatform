# ================================================================
# Secrets Manager Module
#
# Creates placeholder secrets for all sensitive configuration.
# IMPORTANT: Terraform creates the secret CONTAINERS with empty/
# placeholder values. Real values must be set MANUALLY via the
# AWS Console or CLI BEFORE applying the ECS module.
#
# Secret layout (JSON objects per logical group):
#   /chatproxy/{env}/jwt                → { JWT_ACCESS_SECRET, JWT_REFRESH_SECRET }
#   /chatproxy/{env}/db/accounting      → { DB_USER, DB_PASSWORD }
#   /chatproxy/{env}/db/flowise         → { POSTGRES_USER, POSTGRES_PASSWORD }
#   /chatproxy/{env}/mongodb/auth       → { MONGODB_URI }
#   /chatproxy/{env}/mongodb/proxy      → { MONGODB_URL }
#   /chatproxy/{env}/flowise/api-key    → { FLOWISE_API_KEY }
#   /chatproxy/{env}/flowise/config     → { FLOWISE_SECRETKEY_OVERWRITE, FLOWISE_USERNAME, FLOWISE_PASSWORD }
#   /chatproxy/{env}/ses                → { SMTP_USER, SMTP_PASS }
#
# How to populate secrets after 'terraform apply':
#   aws secretsmanager put-secret-value \
#     --secret-id /chatproxy/dev/jwt \
#     --secret-string '{"JWT_ACCESS_SECRET":"<your-value>","JWT_REFRESH_SECRET":"<your-value>"}'
# ================================================================

locals {
  name_prefix = "${var.project}-${var.env}"

  # Map of secret path suffix → description
  # Values are managed externally (AWS CLI / Console) — NOT by Terraform.
  secrets = {
    "jwt" = {
      description = "JWT signing secrets shared by auth-service, accounting-service, and flowise-proxy"
    }
    "db/accounting" = {
      description = "PostgreSQL credentials for accounting-service (RDS Aurora)"
    }
    "db/flowise" = {
      description = "PostgreSQL credentials for Flowise AI engine (RDS Aurora)"
    }
    "mongodb/auth" = {
      description = "MongoDB connection URI for auth-service (EC2 MongoDB)"
    }
    "mongodb/proxy" = {
      description = "MongoDB connection URL for flowise-proxy service (EC2 MongoDB)"
    }
    "flowise/api-key" = {
      description = "Flowise AI engine API key used by flowise-proxy to authenticate requests"
    }
    "flowise/config" = {
      description = "Flowise runtime config (FLOWISE_SECRETKEY_OVERWRITE, FLOWISE_USERNAME, FLOWISE_PASSWORD)"
    }
    "ses" = {
      description = "Amazon SES SMTP credentials for auth-service email delivery"
    }
  }
}

resource "aws_secretsmanager_secret" "secrets" {
  for_each = local.secrets

  name        = "/${var.project}/${var.env}/${each.key}"
  description = each.value.description

  # Recovery window: 7 days in prod, 0 in dev (immediate delete for easy cleanup)
  recovery_window_in_days = var.env == "prod" ? 7 : 0

  tags = merge(var.tags, {
    Name    = "/${var.project}/${var.env}/${each.key}"
    Env     = var.env
    Project = var.project
  })
}

# Secret values are managed externally via AWS CLI / Console (see AWS_SETUP_GUIDE.md Part 10).
# Terraform only manages the secret containers (name, description, tags, recovery window).
# This prevents Terraform from ever overwriting real values with placeholders on 'terraform apply'.
