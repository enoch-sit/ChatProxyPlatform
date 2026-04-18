# ================================================================
# Flowise Proxy Service ECS Module
#
# Deploys the flowise-proxy-service-py (FastAPI/Python) as an ECS
# Fargate task behind the shared platform ALB.
#
# Path rules:
#   /api/v1/chat      → priority 120
#   /api/v1/chat/*    → priority 120
#   /api/v1/admin     → priority 120
#   /api/v1/admin/*   → priority 120
#
# Secrets injected:
#   JWT_ACCESS_SECRET   — from jwt secret
#   JWT_REFRESH_SECRET  — from jwt secret
#   FLOWISE_API_KEY     — from flowise/api-key secret
#   MONGODB_URL         — from mongodb/proxy secret (full connection string)
#
# Plain env vars:
#   FLOWISE_API_URL     — flowise ALB URL
#   AUTH_API_URL        — platform ALB /api/auth URL
#   ACCOUNTING_API_URL  — platform ALB /api/accounting URL
#   CORS_ORIGIN         — domain origin
#
# Health check: GET /health  (port 8000)
# ================================================================

locals {
  name_prefix = "${var.project}-${var.environment}-flowise-proxy"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 14
}

# ── ECS Task Execution IAM Role ───────────────────────────────────────

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
        var.secret_flowise_api_key_arn,
        var.secret_mongodb_proxy_arn,
      ]
    }]
  })
}

# ── ECS Task Definition ───────────────────────────────────────────────

resource "aws_ecs_task_definition" "proxy" {
  family                   = "${local.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "flowise-proxy"
    image     = var.image
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "FLOWISE_API_URL",          value = var.flowise_api_url },
      { name = "AUTH_API_URL",             value = "https://${var.domain_name}/api/auth" },
      { name = "EXTERNAL_AUTH_URL",        value = "https://${var.domain_name}" },
      { name = "ACCOUNTING_API_URL",       value = "https://${var.domain_name}/api/accounting" },
      { name = "ACCOUNTING_SERVICE_URL",   value = "https://${var.domain_name}" },
      { name = "CORS_ORIGIN",              value = "https://${var.domain_name}" },
      { name = "PORT",                     value = "8000" },
      { name = "DEBUG",                    value = "false" },
      { name = "MONGODB_DATABASE_NAME",    value = "proxy_db" },
    ]

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
        name      = "FLOWISE_API_KEY"
        valueFrom = "${var.secret_flowise_api_key_arn}:FLOWISE_API_KEY::"
      },
      {
        name      = "MONGODB_URL"
        valueFrom = "${var.secret_mongodb_proxy_arn}:MONGODB_URL::"
      },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.proxy.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "flowise-proxy"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -sf http://localhost:8000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ── ALB Target Group ──────────────────────────────────────────────────

resource "aws_lb_target_group" "proxy" {
  name                 = "${local.name_prefix}-tg"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ── ALB Listener Rule — /api/v1/chat and /api/v1/admin prefix ────────

resource "aws_lb_listener_rule" "proxy" {
  listener_arn = var.https_listener_arn
  priority     = 120

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/chat*", "/api/v1/admin*", "/api/v1/chatflows*"]
    }
  }
}

# ── ECS Service ───────────────────────────────────────────────────────

resource "aws_ecs_service" "proxy" {
  name            = "${local.name_prefix}-service"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.proxy.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.proxy.arn
    container_name   = "flowise-proxy"
    container_port   = 8000
  }

  depends_on = [
    aws_iam_role_policy_attachment.task_exec_managed,
    aws_lb_listener_rule.proxy,
  ]
}
