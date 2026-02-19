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
