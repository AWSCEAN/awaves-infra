# =============================================================================
# SageMaker Security Group (VPC mode — self-referencing rule required)
# =============================================================================

resource "aws_security_group" "domain" {
  name        = "${var.name}-sagemaker-domain"
  description = "SageMaker domain (VPC mode) - intra-cluster communication"
  vpc_id      = var.vpc_id

  # SageMaker VPC mode requires self-referencing ingress
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sagemaker-domain"
  }
}

# =============================================================================
# SageMaker Domain (Studio — VPC-only mode)
# Note: Creates an EFS file system (~$0.30/GB/month) for Studio storage
# =============================================================================

resource "aws_sagemaker_domain" "this" {
  domain_name             = var.name
  auth_mode               = "IAM"
  vpc_id                  = var.vpc_id
  subnet_ids              = var.private_subnet_ids
  app_network_access_type = "VpcOnly"

  default_user_settings {
    execution_role  = var.sagemaker_execution_role_arn
    security_groups = [aws_security_group.domain.id]
  }

  domain_settings {
    execution_role_identity_config = "USER_PROFILE_NAME"
  }

  tags = {
    Name = var.name
  }
}

# =============================================================================
# Model Package Group (Model Registry)
# Versioned model registry: surf-index models (XGBoost / LightGBM)
# Model 1 ... Model N — managed by SageMaker Pipelines evaluation step
# =============================================================================

resource "aws_sagemaker_model_package_group" "surf_index" {
  model_package_group_name        = "${var.name}-surf-index"
  model_package_group_description = "awaves surf index model registry (XGBoost / LightGBM)"

  tags = {
    Name = "${var.name}-surf-index"
  }
}
