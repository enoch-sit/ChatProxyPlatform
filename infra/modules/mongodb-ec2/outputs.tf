output "private_ip" {
  description = "Private IP address of the MongoDB EC2 instance"
  value       = aws_instance.mongodb.private_ip
}

output "instance_id" {
  description = "EC2 instance ID (use for SSM Session Manager)"
  value       = aws_instance.mongodb.id
}

output "mongodb_sg_id" {
  description = "Security group ID of the MongoDB instance"
  value       = aws_security_group.mongodb.id
}
