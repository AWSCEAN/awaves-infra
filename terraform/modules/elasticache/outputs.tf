output "replication_group_id" {
  description = "ElastiCache replication group ID"
  value       = aws_elasticache_replication_group.valkey.id
}

output "primary_endpoint" {
  description = "ElastiCache primary endpoint address"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "security_group_id" {
  description = "ElastiCache security group ID"
  value       = aws_security_group.elasticache.id
}
