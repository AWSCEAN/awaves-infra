# =============================================================================
# VPC
# =============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.networking.vpc_cidr_block
}

# =============================================================================
# Subnets
# =============================================================================

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = module.networking.database_subnet_ids
}

# =============================================================================
# Subnet Groups
# =============================================================================

output "database_subnet_group_name" {
  description = "Name of the database subnet group (used by Aurora and ElastiCache)"
  value       = module.networking.database_subnet_group_name
}

# =============================================================================
# VPC Endpoints
# =============================================================================

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC endpoint"
  value       = module.networking.vpc_endpoint_s3_id
}

output "vpc_endpoint_dynamodb_id" {
  description = "ID of the DynamoDB VPC endpoint"
  value       = module.networking.vpc_endpoint_dynamodb_id
}

# =============================================================================
# S3 Buckets
# =============================================================================

output "s3_bucket_frontend" {
  description = "Frontend S3 bucket name"
  value       = module.s3.bucket_frontend
}

output "s3_bucket_datalake" {
  description = "Datalake S3 bucket name (raw, processed, inference, spots)"
  value       = module.s3.bucket_datalake
}

output "s3_bucket_ml" {
  description = "ML S3 bucket name (training, models, pipeline, drift)"
  value       = module.s3.bucket_ml
}

# =============================================================================
# DynamoDB Tables
# =============================================================================

output "dynamodb_table_surf_data_name" {
  description = "Name of the surf data DynamoDB table"
  value       = module.dynamodb.table_surf_data_name
}

output "dynamodb_table_surf_data_arn" {
  description = "ARN of the surf data DynamoDB table"
  value       = module.dynamodb.table_surf_data_arn
}

output "dynamodb_table_saved_list_name" {
  description = "Name of the saved list DynamoDB table"
  value       = module.dynamodb.table_saved_list_name
}

output "dynamodb_table_saved_list_arn" {
  description = "ARN of the saved list DynamoDB table"
  value       = module.dynamodb.table_saved_list_arn
}

# =============================================================================
# ECR Repositories
# =============================================================================

output "ecr_web_app_url" {
  description = "ECR repository URL for web app"
  value       = module.ecr.repository_web_app_url
}

output "ecr_mobile_app_url" {
  description = "ECR repository URL for mobile app"
  value       = module.ecr.repository_mobile_app_url
}

output "ecr_backend_api_url" {
  description = "ECR repository URL for backend API"
  value       = module.ecr.repository_backend_api_url
}

# =============================================================================
# IAM Roles
# =============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.iam.lambda_execution_role_arn
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = module.iam.sagemaker_execution_role_arn
}

# =============================================================================
# SNS
# =============================================================================

output "sns_alerts_topic_arn" {
  description = "ARN of the alerts SNS topic"
  value       = module.sns.alerts_topic_arn
}

# =============================================================================
# Step Functions
# =============================================================================

output "step_functions_state_machine_arn" {
  description = "ARN of the data collection state machine"
  value       = module.step_functions.state_machine_arn
}

# =============================================================================
# EventBridge
# =============================================================================

output "eventbridge_schedule_name" {
  description = "Name of the EventBridge schedule (DISABLED by default)"
  value       = module.eventbridge.schedule_name
}

# =============================================================================
# SageMaker
# =============================================================================

output "sagemaker_domain_id" {
  description = "SageMaker Studio domain ID"
  value       = module.sagemaker.domain_id
}

output "sagemaker_domain_url" {
  description = "SageMaker Studio domain URL"
  value       = module.sagemaker.domain_url
}

output "sagemaker_model_package_group_name" {
  description = "Model registry group name (surf-index)"
  value       = module.sagemaker.model_package_group_name
}

# =============================================================================
# CloudWatch
# =============================================================================

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = module.cloudwatch.dashboard_name
}
