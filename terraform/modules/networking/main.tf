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
