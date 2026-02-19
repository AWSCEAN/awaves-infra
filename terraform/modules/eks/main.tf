# =============================================================================
# EKS Cluster
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.name
  cluster_version = "1.31"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Public access for kubectl (dev only)
  cluster_endpoint_public_access = true

  # Managed node group
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 3
      desired_size   = 3

      subnet_ids = var.private_subnet_ids
    }
  }

  tags = {
    Name = var.name
  }
}
