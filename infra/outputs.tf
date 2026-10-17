output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, one per Availability Zone."
  value       = [for s in aws_subnet.private : s.id]
}

output "flow_log_group" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = aws_cloudwatch_log_group.flow.name
}
