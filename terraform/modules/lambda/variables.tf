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

variable "dynamodb_table_surf_data" {
  description = "Surf data DynamoDB table name"
  type        = string
}

variable "sns_alerts_topic_arn" {
  description = "ARN of the SNS alerts topic"
  type        = string
}

variable "discord_webhook_url" {
  description = "Discord webhook URL for alerts (leave empty to skip)"
  type        = string
  default     = ""
}
