variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
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

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS — allowed to connect)"
  type        = list(string)
}

variable "database_subnet_ids" {
  description = "List of database subnet IDs (OpenSearch is placed in the first AZ)"
  type        = list(string)
}

variable "create_service_linked_role" {
  description = "Set to false if the es.amazonaws.com service-linked role already exists in the account"
  type        = bool
  default     = true
}
