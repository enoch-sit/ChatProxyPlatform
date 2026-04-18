# ================================================================
# RDS PostgreSQL Module
#
# Creates a single-AZ RDS PostgreSQL t4g.micro instance for the
# accounting service. Credentials are read from the existing
# Secrets Manager secret (db/accounting) so they stay in sync.
#
# Placed in private subnets — only reachable from ECS tasks SG.
# ================================================================

locals {
  name_prefix = "${var.project}-${var.environment}-accounting-db"
}

# ── Read existing accounting credentials from Secrets Manager ────────

data "aws_secretsmanager_secret_version" "accounting" {
  secret_id = var.secret_db_accounting_arn
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.accounting.secret_string)
}

# ── DB Subnet Group (private subnets) ────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-subnet-group"
  description = "Private subnets for accounting RDS"
  subnet_ids  = var.subnet_ids

  tags = { Name = "${local.name_prefix}-subnet-group" }
}

# ── Security Group — allow 5432 from ECS tasks only ──────────────────

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg"
  description = "Allow PostgreSQL from ECS tasks only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_tasks_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg" }
}

# ── Parameter Group — disable forced SSL (app connects without SSL) ──

resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-pg"
  family      = "postgres16"
  description = "Accounting RDS parameter group"

  parameter {
    name  = "rds.force_ssl"
    value = "0"
  }

  tags = { Name = "${local.name_prefix}-pg" }
}

# ── RDS PostgreSQL Instance ───────────────────────────────────────────

resource "aws_db_instance" "this" {
  identifier     = local.name_prefix
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100 # auto-scaling up to 100 GB
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = local.db_creds["DB_USER"]
  password = local.db_creds["DB_PASSWORD"]
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az            = false # single-AZ for dev cost savings
  publicly_accessible = false

  # Backups
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  # Dev settings — allow destroy without snapshot
  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = local.name_prefix }
}
