output "service_name" {
  value = aws_ecs_service.bridge.name
}

output "target_group_arn" {
  value = aws_lb_target_group.bridge.arn
}
