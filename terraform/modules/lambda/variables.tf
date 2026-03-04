variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  type        = string
}

variable "s3_bucket_datalake" {
  description = "Datalake S3 bucket name (raw, processed, inference, spots)"
  type        = string
}

variable "s3_bucket_ml" {
  description = "ML S3 bucket name (training, models, pipeline, drift)"
  type        = string
}

variable "dynamodb_table_surf_info" {
  description = "Surf info DynamoDB table name"
  type        = string
}

variable "dynamodb_table_saved_list" {
  description = "Saved list DynamoDB table name"
  type        = string
}

variable "elasticache_endpoint" {
  description = "ElastiCache primary endpoint address"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID for Lambda VPC config (required for ElastiCache access)"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Lambda VPC config (required for ElastiCache access)"
  type        = list(string)
  default     = []
}

variable "model_version" {
  description = "SageMaker model version label written to DynamoDB metadata"
  type        = string
  default     = "awaves-v1"
}

variable "sns_alerts_topic_arn" {
  description = "ARN of the SNS alerts topic"
  type        = string
}

variable "discord_deploy_webhook_url" {
  description = "Discord webhook URL for deploy/infra alerts"
  type        = string
  default     = ""
}

variable "discord_error_webhook_url" {
  description = "Discord webhook URL for error/monitoring alerts"
  type        = string
  default     = ""
}

variable "discord_ml_webhook_url" {
  description = "Discord webhook URL for ML pipeline alerts"
  type        = string
  default     = ""
}

variable "bedrock_model_id" {
  description = "Bedrock model ID for surf summary generation"
  type        = string
  default     = "us.anthropic.claude-3-7-sonnet-20250219-v1:0"
}

variable "sagemaker_pipeline_arn" {
  description = "ARN of the SageMaker training pipeline (triggered by drift_detection on isDrift=true)"
  type        = string
  default     = ""
}

variable "hourly_model_package_group_name" {
  description = "SageMaker Model Package Group name for hourly model (triggers cache invalidation on Approved)"
  type        = string
  default     = ""
}

variable "inference_state_machine_arn" {
  description = "ARN of the batch inference Step Functions state machine (triggered after model approval)"
  type        = string
  default     = ""
}

variable "sagemaker_endpoint_name" {
  description = "SageMaker real-time endpoint name for on-demand surf score inference (bedrock_summary fallback)"
  type        = string
  default     = ""
}
