output "redis_cluster_id" {
  description = "ID of the Redis cluster"
  value       = aws_elasticache_cluster.main.id
}

output "redis_endpoint" {
  description = "Endpoint address of the Redis cluster"
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "redis_port" {
  description = "Port of the Redis cluster"
  value       = aws_elasticache_cluster.main.port
}

output "redis_arn" {
  description = "ARN of the Redis cluster"
  value       = aws_elasticache_cluster.main.arn
}
