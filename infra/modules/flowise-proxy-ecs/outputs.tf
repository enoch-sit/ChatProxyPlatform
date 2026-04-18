output "service_name" {
  value = aws_ecs_service.proxy.name
}

output "target_group_arn" {
  value = aws_lb_target_group.proxy.arn
}
