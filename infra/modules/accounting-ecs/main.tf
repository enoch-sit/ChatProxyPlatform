# ================================================================
# Accounting Service ECS Module
#
# Deploys the accounting-service as an ECS Fargate task and registers
# it with the shared platform ALB under path prefix /api/accounting*.
#
# DB_HOST is passed as a plain env var (the RDS endpoint is not secret).
# DB_USER and DB_PASSWORD are injected from Secrets Manager.
# JWT_ACCESS_SECRET is injected for token verification middleware.
#
# Health check: GET /health  (port 3001)
# ================================================================

locals {
  name_prefix = "${var.project}-${var.environment}-accounting"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "accounting" {
  name              = "/ecs/${var.project}-${var.environment}-accounting"
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
        var.secret_db_accounting_arn,
        var.secret_jwt_arn,
      ]
    }]
  })
}

# ── ECS Task Definition ───────────────────────────────────────────────

resource "aws_ecs_task_definition" "accounting" {
  family                   = "${local.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "accounting"
    image     = var.image
    essential = true

    portMappings = [{
      containerPort = 3001
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT",         value = "3001" },
      { name = "NODE_ENV",     value = "production" },
      { name = "DB_HOST",      value = var.db_host },
      { name = "DB_PORT",      value = tostring(var.db_port) },
      { name = "DB_NAME",      value = var.db_name },
      { name = "CORS_ORIGIN",  value = "https://${var.domain_name}" },
    ]

    secrets = [
      {
        name      = "DB_USER"
        valueFrom = "${var.secret_db_accounting_arn}:DB_USER::"
      },
      {
        name      = "DB_PASSWORD"
        valueFrom = "${var.secret_db_accounting_arn}:DB_PASSWORD::"
      },
      {
        name      = "JWT_ACCESS_SECRET"
        valueFrom = "${var.secret_jwt_arn}:JWT_ACCESS_SECRET::"
      },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.accounting.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "accounting"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -qO- http://localhost:3001/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
}

# ── ALB Target Group ──────────────────────────────────────────────────

resource "aws_lb_target_group" "accounting" {
  name        = "${local.name_prefix}-tg"
  port        = 3001
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

resource "aws_lb_listener_rule" "accounting" {
  listener_arn = var.https_listener_arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.accounting.arn
  }

  condition {
    path_pattern {
      values = ["/api/accounting", "/api/accounting/*", "/api/credits*", "/api/usage*"]
    }
  }
}

# ── ECS Service ───────────────────────────────────────────────────────

resource "aws_ecs_service" "accounting" {
  name            = "${local.name_prefix}-service"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.accounting.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.accounting.arn
    container_name   = "accounting"
    container_port   = 3001
  }

  depends_on = [aws_lb_listener_rule.accounting]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
