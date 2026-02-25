# =============================================================================
# Service-Linked Role (required for VPC placement)
# Set create_service_linked_role = false if it already exists in the account
# =============================================================================

resource "aws_iam_service_linked_role" "opensearch" {
  count                = var.create_service_linked_role ? 1 : 0
  aws_service_name     = "es.amazonaws.com"
  description          = "Service-linked role for Amazon OpenSearch Service"
}

# IAM changes take time to propagate globally before OpenSearch can use the role
resource "time_sleep" "wait_for_service_linked_role" {
  count           = var.create_service_linked_role ? 1 : 0
  depends_on      = [aws_iam_service_linked_role.opensearch]
  create_duration = "15s"
}

# =============================================================================
# Security Group
# =============================================================================

resource "aws_security_group" "opensearch" {
  name_prefix = "${var.name}-opensearch-"
  description = "Security group for OpenSearch Service"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from private subnets (EKS)"
    from_port   = 443
    to_port     = 443
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
    Name = "${var.name}-opensearch-sg"
  }
}

# =============================================================================
# OpenSearch Domain
# =============================================================================

resource "aws_opensearch_domain" "this" {
  domain_name    = "${var.name}-spots"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type            = "t3.small.search"
    instance_count           = 1
    dedicated_master_enabled = false
    zone_awareness_enabled   = false
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  vpc_options {
    subnet_ids         = [var.database_subnet_ids[0]]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # VPC-based domain: network access is controlled by the security group.
  # Access policy allows all principals within the VPC.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "es:*"
      Resource  = "arn:aws:es:${var.aws_region}:${var.account_id}:domain/${var.name}-spots/*"
    }]
  })

  tags = {
    Name = "${var.name}-opensearch"
  }

  depends_on = [
    aws_iam_service_linked_role.opensearch,
    time_sleep.wait_for_service_linked_role,
  ]
}
