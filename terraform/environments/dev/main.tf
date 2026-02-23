locals {
  name = "${var.project_name}-${var.environment}"
}

# =============================================================================
# Networking (VPC + Endpoints)
# =============================================================================

module "networking" {
  source = "../../modules/networking"

  name                  = local.name
  aws_region            = var.aws_region
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
}

# =============================================================================
# S3 Buckets
# =============================================================================

module "s3" {
  source = "../../modules/s3"

  project     = var.project_name
  environment = var.environment
}

# =============================================================================
# DynamoDB Tables
# =============================================================================

module "dynamodb" {
  source = "../../modules/dynamodb"

  name = local.name
}

# =============================================================================
# ECR Repositories
# =============================================================================

module "ecr" {
  source = "../../modules/ecr"

  name = local.name
}

# =============================================================================
# IAM Roles & Policies
# =============================================================================

data "aws_caller_identity" "current" {}

module "iam" {
  source = "../../modules/iam"

  name            = local.name
  aws_region      = var.aws_region
  account_id      = data.aws_caller_identity.current.account_id
  bucket_datalake = module.s3.bucket_datalake
  bucket_ml       = module.s3.bucket_ml
  github_org      = var.github_org
  github_repo     = var.github_repo
}

# =============================================================================
# SNS
# =============================================================================

module "sns" {
  source = "../../modules/sns"

  name = local.name
}

# =============================================================================
# Lambda Functions
# =============================================================================

module "lambda" {
  source = "../../modules/lambda"

  name                      = local.name
  environment               = var.environment
  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  s3_bucket_datalake        = module.s3.bucket_datalake
  s3_bucket_ml              = module.s3.bucket_ml
  dynamodb_table_surf_info  = module.dynamodb.table_surf_info_name
  sns_alerts_topic_arn      = module.sns.alerts_topic_arn
  bedrock_model_id          = "us.anthropic.claude-3-5-haiku-20241022-v1:0"
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  elasticache_endpoint      = module.elasticache.primary_endpoint
}

# =============================================================================
# Step Functions (Data Collection Pipeline)
# =============================================================================

module "step_functions" {
  source = "../../modules/step_functions"

  name                         = local.name
  lambda_api_call_arn          = module.lambda.api_call_arn
  lambda_preprocessing_arn     = module.lambda.preprocessing_arn
  lambda_drift_detection_arn   = module.lambda.drift_detection_arn
  lambda_save_arn              = module.lambda.save_arn
  s3_bucket_datalake           = module.s3.bucket_datalake
  sagemaker_execution_role_arn = module.iam.sagemaker_execution_role_arn
}

# =============================================================================
# EventBridge (Scheduled Trigger - DISABLED by default)
# =============================================================================

module "eventbridge" {
  source = "../../modules/eventbridge"

  name              = local.name
  state_machine_arn = module.step_functions.state_machine_arn
}

# =============================================================================
# SageMaker (Studio Domain + Model Registry)
# =============================================================================

module "sagemaker" {
  source = "../../modules/sagemaker"

  name                         = local.name
  vpc_id                       = module.networking.vpc_id
  private_subnet_ids           = module.networking.private_subnet_ids
  sagemaker_execution_role_arn = module.iam.sagemaker_execution_role_arn
}

# =============================================================================
# CloudWatch (Log Groups + Alarms + Dashboard)
# =============================================================================

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  name                 = local.name
  aws_region           = var.aws_region
  sns_alerts_topic_arn = module.sns.alerts_topic_arn
  # step_functions_state_machine_arn: connected in Phase 3 after step_functions is applied
}

# =============================================================================
# X-Ray (Tracing)
# =============================================================================

module "xray" {
  source = "../../modules/xray"

  name = local.name
}

# =============================================================================
# EKS Cluster
# =============================================================================

module "eks" {
  source = "../../modules/eks"

  name               = local.name
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  account_id         = data.aws_caller_identity.current.account_id
}

# =============================================================================
# EKS Add-ons: AWS Load Balancer Controller
# =============================================================================

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.lb_controller_role_arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.networking.vpc_id
  }

  depends_on = [module.eks]
}

# =============================================================================
# EKS Add-ons: Metrics Server (for HPA)
# =============================================================================

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"
  namespace  = "kube-system"

  depends_on = [module.eks]
}

# =============================================================================
# Kubernetes Namespace
# =============================================================================

resource "kubernetes_namespace" "awaves" {
  metadata {
    name = "${local.name}"
    labels = {
      name = "${local.name}"
    }
  }

  depends_on = [module.eks]
}

# =============================================================================
# Aurora PostgreSQL
# =============================================================================

module "rds" {
  source = "../../modules/rds"

  name                       = local.name
  vpc_id                     = module.networking.vpc_id
  private_subnet_cidrs       = var.private_subnet_cidrs
  database_subnet_group_name = module.networking.database_subnet_group_name
}

# =============================================================================
# ElastiCache for Valkey
# =============================================================================

module "elasticache" {
  source = "../../modules/elasticache"

  name                 = local.name
  vpc_id               = module.networking.vpc_id
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_ids  = module.networking.database_subnet_ids
}

# =============================================================================
# CloudFront (S3 frontend origin, ALB API origin 추후 추가)
# =============================================================================

module "cloudfront" {
  source = "../../modules/cloudfront"

  name                             = local.name
  s3_bucket_id                     = module.s3.bucket_frontend
  s3_bucket_arn                    = module.s3.bucket_frontend_arn
  s3_bucket_regional_domain_name   = module.s3.bucket_frontend_regional_domain_name
  # alb_dns_name: EKS Ingress 배포 후 추가
  # domain_name: Route 53 도메인 연결 시 추가
  # acm_certificate_arn: ACM 인증서 발급 후 추가
}
