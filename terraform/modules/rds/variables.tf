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

variable "database_subnet_group_name" {
  description = "Name of the database subnet group"
  type        = string
}

variable "extra_ingress_cidrs" {
  description = "Additional CIDR blocks allowed to connect to Aurora (e.g. developer IPs for testing)"
  type        = list(string)
  default     = []
}
