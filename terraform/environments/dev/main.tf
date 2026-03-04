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
  dynamodb_table_saved_list = module.dynamodb.table_saved_list_name
  sns_alerts_topic_arn           = module.sns.alerts_topic_arn
  discord_deploy_webhook_url     = var.discord_deploy_webhook_url
  discord_error_webhook_url      = var.discord_error_webhook_url
  discord_ml_webhook_url         = var.discord_ml_webhook_url
  bedrock_model_id          = "us.anthropic.claude-3-7-sonnet-20250219-v1:0"
  vpc_id                    = module.networking.vpc_id
  private_subnet_ids        = module.networking.private_subnet_ids
  elasticache_endpoint      = module.elasticache.primary_endpoint
  # Constructed ARN/name to avoid circular dependency with module.sagemaker / module.step_functions
  sagemaker_pipeline_arn          = "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:pipeline/${local.name}-training"
  hourly_model_package_group_name = "${local.name}-surf-index"
  sagemaker_endpoint_name         = "${local.name}-surf-index"
  inference_state_machine_arn     = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.name}-batch-inference"
}

# =============================================================================
# Step Functions (Data Collection Pipeline)
# =============================================================================

module "step_functions" {
  source = "../../modules/step_functions"

  name                         = local.name
  lambda_api_call_arn          = module.lambda.api_call_arn
  lambda_data_validation_arn   = module.lambda.data_validation_arn
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
  s3_bucket_ml                 = module.s3.bucket_ml
  s3_bucket_datalake           = module.s3.bucket_datalake
  account_id                   = data.aws_caller_identity.current.account_id
  aws_region                   = var.aws_region
  lambda_alert_ml_pipeline_arn        = module.lambda.alert_ml_pipeline_arn
  lambda_data_collection_training_arn = module.lambda.data_collection_training_arn
  # Set after first training run, e.g.:
  # model_data_url = "s3://awaves-ml-dev/models/<job-name>/output/model.tar.gz"
  model_data_url         = var.sagemaker_model_data_url
  weekly_model_data_url  = var.sagemaker_weekly_model_data_url

  depends_on = [module.lambda]
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
    name = local.name
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
  extra_ingress_cidrs        = ["118.218.200.33/32"]
}

# =============================================================================
# OpenSearch Service (surf spot full-text search)
# =============================================================================

module "opensearch" {
  source = "../../modules/opensearch"

  name                 = local.name
  vpc_id               = module.networking.vpc_id
  aws_region           = var.aws_region
  account_id           = data.aws_caller_identity.current.account_id
  private_subnet_cidrs = var.private_subnet_cidrs
  database_subnet_ids  = module.networking.database_subnet_ids
  # create_service_linked_role = false  # uncomment if role already exists in account
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
# Route 53 - Hosted Zone
# =============================================================================

module "route53" {
  source = "../../modules/route53"

  domain_name = var.domain_name
}

# =============================================================================
# ACM Certificate (us-east-1 — required for CloudFront)
# DNS validation records are created in Route 53 automatically
# =============================================================================

module "acm" {
  source = "../../modules/acm"

  domain_name = var.domain_name
  zone_id     = module.route53.zone_id
}

# =============================================================================
# CloudFront (S3 frontend origin, ALB API origin 추후 추가)
# =============================================================================

module "cloudfront" {
  source = "../../modules/cloudfront"

  name                           = local.name
  s3_bucket_id                   = module.s3.bucket_frontend
  s3_bucket_arn                  = module.s3.bucket_frontend_arn
  s3_bucket_regional_domain_name = module.s3.bucket_frontend_regional_domain_name
  domain_names                   = ["cdn.awaves.net"]
  acm_certificate_arn            = module.acm.certificate_arn
  alb_dns_name                   = var.alb_dns_name
}

# =============================================================================
# CloudFront Distribution 2: awaves.net / www.awaves.net (SPA + API)
# Distribution 1 (cdn.awaves.net) is managed by module.cloudfront above
# Each distribution uses its own OAC:
#   Distribution 1 OAC: managed inside module.cloudfront (import: E3MW5MNGNFYLJV)
#   Distribution 2 OAC: aws_cloudfront_origin_access_control.main (import: E10LQZJGURKL2M)
# =============================================================================

resource "aws_cloudfront_origin_access_control" "main" {
  name                              = "${local.name}-frontend-oac"
  description                       = "OAC for awaves frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  http_version        = "http2"
  aliases             = [var.domain_name, "www.${var.domain_name}"]

  origin {
    domain_name              = module.s3.bucket_frontend_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.main.id
  }

  origin {
    domain_name = "k8s-awavesde-webappin-35d6501f04-249418890.us-east-1.elb.amazonaws.com"
    origin_id   = "alb-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    default_ttl = 86400
    max_ttl     = 31536000
    min_ttl     = 0
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-api"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin", "Accept", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
      cookies {
        forward = "all"
      }
    }

    default_ttl = 0
    max_ttl     = 0
    min_ttl     = 0
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = module.acm.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name = "${local.name}-cloudfront"
  }

  depends_on = [module.cloudfront]
}

# =============================================================================
# Route 53 - A Alias Records (CloudFront)
# apex/www → distribution 2 (awaves.net), cdn → distribution 1 (module.cloudfront)
# =============================================================================

resource "aws_route53_record" "apex" {
  zone_id = module.route53.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = module.route53.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
