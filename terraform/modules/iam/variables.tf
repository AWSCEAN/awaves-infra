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
  description = "Datalake S3 bucket name"
  type        = string
}

variable "bucket_ml" {
  description = "ML S3 bucket name"
  type        = string
}

variable "infra_users" {
  description = "IAM usernames for the infra group (MLOps & Infra)"
  type        = list(string)
  default     = ["awaves-jkwon", "awaves-mudd"]
}

variable "dev_users" {
  description = "IAM usernames for the dev group (FE/BE)"
  type        = list(string)
  default     = ["awaves-bhgdwn", "awaves-jlee", "awaves-hpark"]
}
