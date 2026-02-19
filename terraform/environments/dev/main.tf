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
  dynamodb_table_surf_data  = module.dynamodb.table_surf_data_name
  sns_alerts_topic_arn      = module.sns.alerts_topic_arn
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

  name                             = local.name
  aws_region                       = var.aws_region
  sns_alerts_topic_arn             = module.sns.alerts_topic_arn
  step_functions_state_machine_arn = module.step_functions.state_machine_arn
}

# =============================================================================
# EKS Cluster
# =============================================================================

module "eks" {
  source = "../../modules/eks"

  name               = local.name
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
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
