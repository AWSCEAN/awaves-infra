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
