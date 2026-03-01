variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for SageMaker domain (VPC mode)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for SageMaker domain"
  type        = list(string)
}

variable "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution IAM role"
  type        = string
}

variable "s3_bucket_ml" {
  description = "ML S3 bucket name (training, models, pipeline, drift)"
  type        = string
}

variable "s3_bucket_datalake" {
  description = "Datalake S3 bucket name (raw, processed, inference)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "lambda_alert_ml_pipeline_arn" {
  description = "ARN of the alert-ml-pipeline Lambda (invoked on bad evaluation)"
  type        = string
}

variable "lambda_data_collection_training_arn" {
  description = "ARN of the data-collection-training Lambda (Step 0 in training pipeline)"
  type        = string
}

variable "qwk_threshold" {
  description = "Minimum QWK score to approve model registration (0.0-1.0)"
  type        = number
  default     = 0.7
}

variable "model_data_url" {
  description = "S3 URI of hourly surf-index model artifact (model.tar.gz). Set after first training run to create the real-time endpoint."
  type        = string
  default     = ""
}

variable "weekly_model_data_url" {
  description = "S3 URI of weekly LightGBM model artifact (model.tar.gz). Set to create the weekly real-time endpoint."
  type        = string
  default     = ""
}
