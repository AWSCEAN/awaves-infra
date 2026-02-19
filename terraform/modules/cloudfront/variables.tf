variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "waf_web_acl_arn" {
  description = "WAF WebACL ARN to associate with CloudFront. Leave empty to disable WAF."
  type        = string
  default     = null
}

variable "s3_bucket_id" {
  description = "Frontend S3 bucket ID"
  type        = string
}

variable "s3_bucket_arn" {
  description = "Frontend S3 bucket ARN"
  type        = string
}

variable "s3_bucket_regional_domain_name" {
  description = "Frontend S3 bucket regional domain name"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS name (backend API origin). Leave empty until EKS Ingress is provisioned."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Custom domain name (e.g. awaves.com). Leave empty to use CloudFront default domain."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN (us-east-1) for custom domain. Leave empty to use CloudFront default cert."
  type        = string
  default     = ""
}
