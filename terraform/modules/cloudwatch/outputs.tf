output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.awaves.dashboard_name
}

output "log_group_lambda_api_call" {
  description = "Log group name for Lambda API Call"
  value       = aws_cloudwatch_log_group.lambda_api_call.name
}

output "log_group_sagemaker" {
  description = "Log group name for SageMaker"
  value       = aws_cloudwatch_log_group.sagemaker.name
}
