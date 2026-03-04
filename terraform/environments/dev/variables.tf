variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "awaves"
}

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS nodes)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets (Aurora, ElastiCache)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

variable "alb_dns_name" {
  description = "ALB DNS name provisioned by EKS Ingress Controller. Set after kubectl apply of Ingress manifest."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Root domain name for the service (e.g. awaves.net)"
  type        = string
  default     = "awaves.net"
}

variable "github_org" {
  description = "GitHub organization name for CI/CD OIDC trust"
  type        = string
  default     = "AWSCEAN"
}

variable "github_repo" {
  description = "GitHub repository name for CI/CD OIDC trust"
  type        = string
  default     = "awaves-agent"
}

variable "sagemaker_model_data_url" {
  description = "S3 URI of trained model artifact (model.tar.gz). Set after first training run to deploy the real-time endpoint."
  type        = string
  default     = ""
}

variable "sagemaker_weekly_model_data_url" {
  description = "S3 URI of weekly LightGBM model artifact (model.tar.gz). Set to deploy the weekly real-time endpoint."
  type        = string
  default     = ""
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

