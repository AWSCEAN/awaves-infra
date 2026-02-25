output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

output "lb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.lb_controller.arn
}

output "backend_api_role_arn" {
  description = "IAM role ARN for backend-api IRSA"
  value       = aws_iam_role.backend_api.arn
}

output "web_app_role_arn" {
  description = "IAM role ARN for web-app IRSA"
  value       = aws_iam_role.web_app.arn
}

output "mobile_app_role_arn" {
  description = "IAM role ARN for mobile-app IRSA"
  value       = aws_iam_role.mobile_app.arn
}
