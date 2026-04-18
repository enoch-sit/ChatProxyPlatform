locals {
  name_prefix = "${var.project}-${var.environment}-bridge"
}

# ─── CloudWatch Logs ────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "bridge" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 7
}

# ─── ECS Task Execution Role ─────────────────────────────────────────────────
resource "aws_iam_role" "task_exec" {
  name = "${local.name_prefix}-task-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_exec_policy" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ─── ECS Task Definition ─────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "bridge" {
  family                   = local.name_prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_exec.arn

  container_definitions = jsonencode([{
    name      = "bridge"
    image     = var.image
    essential = true

    portMappings = [{
      containerPort = 3082
      protocol      = "tcp"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.bridge.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# ─── ALB Target Group ────────────────────────────────────────────────────────
resource "aws_lb_target_group" "bridge" {
  name        = "${local.name_prefix}-tg"
  port        = 3082
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ─── ALB Listener Rule (catch-all, priority 999) ─────────────────────────────
resource "aws_lb_listener_rule" "bridge" {
  listener_arn = var.https_listener_arn
  priority     = 999

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bridge.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# ─── ECS Service ─────────────────────────────────────────────────────────────
resource "aws_ecs_service" "bridge" {
  name            = local.name_prefix
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.bridge.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.bridge.arn
    container_name   = "bridge"
    container_port   = 3082
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_lb_listener_rule.bridge, aws_iam_role_policy_attachment.task_exec_policy]
}
