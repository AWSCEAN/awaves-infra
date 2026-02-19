variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "lambda_api_call_arn" {
  description = "ARN of the API Call Lambda function"
  type        = string
}

variable "lambda_preprocessing_arn" {
  description = "ARN of the Preprocessing Lambda function"
  type        = string
}

variable "lambda_drift_detection_arn" {
  description = "ARN of the Drift Detection Lambda function"
  type        = string
}

variable "lambda_save_arn" {
  description = "ARN of the Save Lambda function"
  type        = string
}

variable "s3_bucket_datalake" {
  description = "Datalake S3 bucket name (inference output path)"
  type        = string
}

variable "sagemaker_execution_role_arn" {
  description = "SageMaker execution role ARN (for iam:PassRole)"
  type        = string
}
