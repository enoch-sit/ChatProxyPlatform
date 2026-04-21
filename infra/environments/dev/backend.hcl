# Terraform Remote State Backend Configuration
# Dev Environment — AWS us-east-1
#
# Used with: terraform init -backend-config=backend.hcl

bucket         = "chatproxy-tfstate-168437900315"
key            = "environments/dev/terraform.tfstate"
region         = "us-east-1"
encrypt        = true
dynamodb_table = "chatproxy-terraform-locks"
