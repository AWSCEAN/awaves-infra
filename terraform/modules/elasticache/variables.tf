variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (allowed to connect)"
  type        = list(string)
}

variable "database_subnet_ids" {
  description = "List of database subnet IDs"
  type        = list(string)
}
