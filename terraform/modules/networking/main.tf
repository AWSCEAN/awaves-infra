# =============================================================================
# VPC
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs              = var.availability_zones
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.database_subnet_cidrs

  # NAT Gateway — required for EKS private subnet nodes
  enable_nat_gateway = true
  single_nat_gateway = true

  # DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet groups (auto-created by the module)
  create_database_subnet_group = true

  # Database subnets do not need internet access
  create_database_subnet_route_table = true

  # EKS-required subnet tags (for future ALB Ingress Controller)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Name = var.name
  }
}

# =============================================================================
# VPC Gateway Endpoints (free)
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    module.vpc.public_route_table_ids,
    module.vpc.private_route_table_ids,
    module.vpc.database_route_table_ids
  )

  tags = {
    Name = "${var.name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"

  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    module.vpc.public_route_table_ids,
    module.vpc.private_route_table_ids,
    module.vpc.database_route_table_ids
  )

  tags = {
    Name = "${var.name}-dynamodb-endpoint"
  }
}

# =============================================================================
# VPC Interface Endpoint: SageMaker Runtime
# Allows EKS pods to invoke SageMaker Endpoints without leaving the VPC.
# Interface endpoint: ~$0.01/AZ-hour — using 1 AZ (private subnet[0]) for cost.
# =============================================================================

resource "aws_security_group" "sagemaker_endpoint" {
  name        = "${var.name}-sagemaker-vpce"
  description = "SageMaker Runtime VPC Interface endpoint"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sagemaker-vpce"
  }
}

resource "aws_vpc_endpoint" "sagemaker_runtime" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sagemaker.runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [module.vpc.private_subnets[0]]
  security_group_ids  = [aws_security_group.sagemaker_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name}-sagemaker-runtime-endpoint"
  }
}
