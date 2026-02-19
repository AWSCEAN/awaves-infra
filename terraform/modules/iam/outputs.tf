output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution.arn
}

output "sagemaker_execution_role_name" {
  description = "Name of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution.name
}

output "infra_group_arn" {
  description = "ARN of the infra IAM group"
  value       = aws_iam_group.infra.arn
}

output "dev_group_arn" {
  description = "ARN of the dev IAM group"
  value       = aws_iam_group.dev.arn
}
