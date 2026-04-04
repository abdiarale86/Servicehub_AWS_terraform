output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = module.elasticache.redis_endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket for attachments"
  value       = module.s3.bucket_name
}

output "ec2_asg_name" {
  description = "Auto Scaling Group name"
  value       = module.ec2.asg_name
}
