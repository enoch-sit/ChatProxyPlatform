# ================================================================
# Auth Service ECS Module
#
# Deploys the auth-service as an ECS Fargate task and registers it
# with the shared platform ALB under the path prefix /api/auth*.
#
# Secrets are injected directly from Secrets Manager into the
# container as environment variables (no secrets in task def JSON).
#
# Health check: GET /health  (registered on the container, not /api/auth/health)
# Route53 record: none (auth is accessed via apex domain path /api/auth/*)
# ================================================================

locals {
  name_prefix = "${var.project}-${var.environment}-auth"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "auth" {
  name              = "/ecs/${var.project}-${var.environment}-auth"
  retention_in_days = 14
}

# ── ECS Task Execution IAM Role ───────────────────────────────────────
# Grants ECS the ability to:
#   1. Pull the image from ECR
#   2. Write logs to CloudWatch
#   3. Read the specific secrets this service needs from Secrets Manager

resource "aws_iam_role" "task_execution" {
  name = "${local.name_prefix}-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "secrets_read" {
  name = "${local.name_prefix}-secrets-read"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [
        var.secret_jwt_arn,
        var.secret_mongodb_auth_arn,
        var.secret_ses_arn,
      ]
    }]
  })
}

# ── ECS Task Definition ───────────────────────────────────────────────

resource "aws_ecs_task_definition" "auth" {
  family                   = "${local.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "auth"
    image     = var.image
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT",                    value = "3000" },
      { name = "NODE_ENV",                value = "production" },
      { name = "JWT_ACCESS_EXPIRES_IN",   value = "1h" },
      { name = "JWT_REFRESH_EXPIRES_IN",  value = "7d" },
      { name = "SMTP_HOST",               value = "email-smtp.us-east-1.amazonaws.com" },
      { name = "SMTP_PORT",               value = "587" },
      { name = "SMTP_SECURE",             value = "false" },
      { name = "EMAIL_FROM",              value = var.ses_from_email },
      { name = "CORS_ORIGIN",             value = "https://${var.domain_name}" },
      { name = "FRONTEND_URL",            value = "https://${var.domain_name}" },
      { name = "BCRYPT_ROUNDS",           value = "10" },
      { name = "MAX_LOGIN_ATTEMPTS",      value = "5" },
      { name = "LOCK_TIME",               value = "15m" },
      { name = "LOG_LEVEL",               value = "info" },
    ]

    # Secrets are injected from Secrets Manager at task startup.
    # Format: "<secret_arn>:<json_key>::" extracts one key from the JSON object.
    secrets = [
      {
        name      = "JWT_ACCESS_SECRET"
        valueFrom = "${var.secret_jwt_arn}:JWT_ACCESS_SECRET::"
      },
      {
        name      = "JWT_REFRESH_SECRET"
        valueFrom = "${var.secret_jwt_arn}:JWT_REFRESH_SECRET::"
      },
      {
        name      = "MONGO_URI"
        valueFrom = "${var.secret_mongodb_auth_arn}:MONGODB_URI::"
      },
      {
        name      = "SMTP_USER"
        valueFrom = "${var.secret_ses_arn}:SMTP_USER::"
      },
      {
        name      = "SMTP_PASS"
        valueFrom = "${var.secret_ses_arn}:SMTP_PASS::"
      },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.auth.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "auth"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ── ALB Target Group ──────────────────────────────────────────────────

resource "aws_lb_target_group" "auth" {
  name        = "${local.name_prefix}-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30
}

# ── HTTPS Listener Rule ───────────────────────────────────────────────
# Routes /api/auth and /api/auth/* to the auth service target group.

resource "aws_lb_listener_rule" "auth" {
  listener_arn = var.https_listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.auth.arn
  }

  condition {
    path_pattern {
      values = ["/api/auth*", "/api/admin*", "/api/testing*", "/api/change-password"]
    }
  }
}

# ── ECS Service ───────────────────────────────────────────────────────

resource "aws_ecs_service" "auth" {
  name            = "${local.name_prefix}-service"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.auth.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Allow Fargate to replace tasks without waiting for old ones to drain
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 180

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = true # required: Fargate needs public IP to pull from ECR
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.auth.arn
    container_name   = "auth"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener_rule.auth]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
