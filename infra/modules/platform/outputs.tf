output "vpc_id" {
  description = "ID of the platform VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB + Fargate tasks)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (MongoDB EC2, RDS)"
  value       = aws_subnet.private[*].id
}

output "alb_sg_id" {
  description = "Security group ID of the platform ALB"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_sg_id" {
  description = "Security group ID shared by all ECS Fargate tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "alb_arn" {
  description = "ARN of the platform ALB"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the platform ALB"
  value       = aws_lb.this.dns_name
}

output "https_listener_arn" {
  description = "ARN of the HTTPS:443 listener (attach listener rules here)"
  value       = aws_lb_listener.https.arn
}

output "ecs_cluster_id" {
  description = "ARN of the shared ECS cluster"
  value       = aws_ecs_cluster.this.id
}

output "ecs_cluster_name" {
  description = "Name of the shared ECS cluster"
  value       = aws_ecs_cluster.this.name
}
