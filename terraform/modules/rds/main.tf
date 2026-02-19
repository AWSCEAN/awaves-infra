# =============================================================================
# Aurora PostgreSQL
# =============================================================================

resource "aws_security_group" "aurora" {
  name_prefix = "${var.name}-aurora-"
  description = "Security group for Aurora PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from private subnets (EKS)"
    from_port   = 5432
    to_port     = 5432
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
    Name = "${var.name}-aurora-sg"
  }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier     = "${var.name}-aurora"
  engine                 = "aurora-postgresql"
  engine_version         = "16.4"
  database_name          = "awaves"
  master_username        = "awaves_admin"
  manage_master_user_password = true

  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  storage_encrypted      = true
  skip_final_snapshot    = true

  tags = {
    Name = "${var.name}-aurora"
  }
}

resource "aws_rds_cluster_instance" "aurora_writer" {
  identifier         = "${var.name}-aurora-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.t4g.medium"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}

resource "aws_rds_cluster_instance" "aurora_reader" {
  count              = 2
  identifier         = "${var.name}-aurora-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.t4g.medium"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}
