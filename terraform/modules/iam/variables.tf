variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "bucket_datalake" {
  description = "Datalake S3 bucket name (data-raw)"
  type        = string
}

variable "bucket_ml" {
  description = "ML S3 bucket name (sagemaker-artifacts)"
  type        = string
}

variable "platform_users" {
  description = "IAM usernames for the platform group (MLOps & Infra)"
  type        = list(string)
  default     = ["awaves-jkwon", "awaves-mudd"]
}

variable "app_users" {
  description = "IAM usernames for the app group (FE/BE/Data Analysis)"
  type        = list(string)
  default     = ["awaves-bhgdwn", "awaves-jlee", "awaves-hpark"]
}

variable "github_org" {
  description = "GitHub organization name for OIDC trust"
  type        = string
  default     = "awaves-project"
}

variable "github_repo" {
  description = "GitHub repository name for OIDC trust"
  type        = string
  default     = "awaves"
}
