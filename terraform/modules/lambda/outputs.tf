output "api_call_arn" {
  description = "ARN of the API Call Lambda function"
  value       = aws_lambda_function.api_call.arn
}

output "preprocessing_arn" {
  description = "ARN of the Preprocessing Lambda function"
  value       = aws_lambda_function.preprocessing.arn
}

output "save_arn" {
  description = "ARN of the Save Lambda function"
  value       = aws_lambda_function.save.arn
}

output "drift_detection_arn" {
  description = "ARN of the Drift Detection Lambda function"
  value       = aws_lambda_function.drift_detection.arn
}

output "alert_monitoring_arn" {
  description = "ARN of the Alert Monitoring Lambda function"
  value       = aws_lambda_function.alert_monitoring.arn
}

output "alert_ml_pipeline_arn" {
  description = "ARN of the Alert ML Pipeline Lambda function"
  value       = aws_lambda_function.alert_ml_pipeline.arn
}

output "api_call_function_name" {
  description = "Name of the API Call Lambda function"
  value       = aws_lambda_function.api_call.function_name
}

output "preprocessing_function_name" {
  description = "Name of the Preprocessing Lambda function"
  value       = aws_lambda_function.preprocessing.function_name
}

output "save_function_name" {
  description = "Name of the Save Lambda function"
  value       = aws_lambda_function.save.function_name
}

output "bedrock_summary_arn" {
  description = "ARN of the Bedrock Summary Lambda function"
  value       = aws_lambda_function.bedrock_summary.arn
}

output "bedrock_summary_function_name" {
  description = "Name of the Bedrock Summary Lambda function"
  value       = aws_lambda_function.bedrock_summary.function_name
}

output "cache_invalidation_arn" {
  description = "ARN of the Cache Invalidation Lambda function"
  value       = aws_lambda_function.cache_invalidation.arn
}

output "cache_invalidation_function_name" {
  description = "Name of the Cache Invalidation Lambda function"
  value       = aws_lambda_function.cache_invalidation.function_name
}
