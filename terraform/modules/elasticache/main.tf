# =============================================================================
# ElastiCache for Valkey
# =============================================================================

resource "aws_security_group" "elasticache" {
  name_prefix = "${var.name}-elasticache-"
  description = "Security group for ElastiCache Valkey"
  vpc_id      = var.vpc_id

  ingress {
    description = "Valkey from private subnets (EKS)"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-elasticache-sg"
  }
}

resource "aws_elasticache_subnet_group" "valkey" {
  name       = "${var.name}-valkey"
  subnet_ids = var.database_subnet_ids
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "${var.name}-valkey"
  description          = "ElastiCache Valkey for awaves"
  engine               = "valkey"
  node_type            = "cache.t4g.micro"
  num_cache_clusters   = 3
  port                 = 6379

  subnet_group_name    = aws_elasticache_subnet_group.valkey.name
  security_group_ids   = [aws_security_group.elasticache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = {
    Name = "${var.name}-valkey"
  }
}
