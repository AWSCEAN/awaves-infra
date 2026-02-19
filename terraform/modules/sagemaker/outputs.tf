output "domain_id" {
  description = "SageMaker domain ID"
  value       = aws_sagemaker_domain.this.id
}

output "domain_url" {
  description = "SageMaker Studio domain URL"
  value       = aws_sagemaker_domain.this.url
}

output "security_group_id" {
  description = "Security group ID for SageMaker domain"
  value       = aws_security_group.domain.id
}

output "model_package_group_name" {
  description = "Model registry group name (surf-index)"
  value       = aws_sagemaker_model_package_group.surf_index.model_package_group_name
}

output "model_package_group_arn" {
  description = "Model registry group ARN"
  value       = aws_sagemaker_model_package_group.surf_index.arn
}
