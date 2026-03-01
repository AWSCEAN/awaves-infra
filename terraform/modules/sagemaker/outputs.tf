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

output "training_pipeline_arn" {
  description = "SageMaker training pipeline ARN (triggered by drift detection Lambda)"
  value       = aws_sagemaker_pipeline.training.arn
}

output "training_pipeline_name" {
  description = "SageMaker training pipeline name"
  value       = aws_sagemaker_pipeline.training.pipeline_name
}

output "endpoint_name" {
  description = "SageMaker real-time endpoint name (empty if model_data_url not set)"
  value       = var.model_data_url != "" ? aws_sagemaker_endpoint.surf_index[0].name : ""
}

output "endpoint_arn" {
  description = "SageMaker real-time endpoint ARN (empty if model_data_url not set)"
  value       = var.model_data_url != "" ? aws_sagemaker_endpoint.surf_index[0].arn : ""
}

output "endpoint_url" {
  description = "SageMaker runtime invocation URL (hourly surf-index)"
  value       = "https://runtime.sagemaker.${var.aws_region}.amazonaws.com/endpoints/${var.name}-surf-index/invocations"
}

output "weekly_endpoint_name" {
  description = "SageMaker weekly endpoint name (empty if weekly_model_data_url not set)"
  value       = var.weekly_model_data_url != "" ? aws_sagemaker_endpoint.weekly[0].name : ""
}

output "weekly_endpoint_arn" {
  description = "SageMaker weekly endpoint ARN (empty if weekly_model_data_url not set)"
  value       = var.weekly_model_data_url != "" ? aws_sagemaker_endpoint.weekly[0].arn : ""
}

output "weekly_endpoint_url" {
  description = "SageMaker runtime invocation URL (weekly LightGBM)"
  value       = "https://runtime.sagemaker.${var.aws_region}.amazonaws.com/endpoints/${var.name}-weekly/invocations"
}
