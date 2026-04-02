output "service_name" {
  description = "Name of the auth ECS service"
  value       = aws_ecs_service.auth.name
}

output "target_group_arn" {
  description = "ARN of the auth ALB target group"
  value       = aws_lb_target_group.auth.arn
}

output "task_definition_arn" {
  description = "ARN of the auth task definition"
  value       = aws_ecs_task_definition.auth.arn
}

output "log_group_name" {
  description = "CloudWatch log group name for auth service"
  value       = aws_cloudwatch_log_group.auth.name
}
