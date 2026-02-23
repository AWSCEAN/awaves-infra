# Service Execution Roles
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

# Human Roles
output "app_admin_role_arn" {
  description = "ARN of the App Admin role"
  value       = aws_iam_role.app_admin.arn
}

output "app_readonly_role_arn" {
  description = "ARN of the App Readonly role"
  value       = aws_iam_role.app_readonly.arn
}

output "infra_admin_role_arn" {
  description = "ARN of the Infra Admin role"
  value       = aws_iam_role.infra_admin.arn
}

output "infra_readonly_role_arn" {
  description = "ARN of the Infra Readonly role"
  value       = aws_iam_role.infra_readonly.arn
}

output "ml_admin_role_arn" {
  description = "ARN of the ML Admin role"
  value       = aws_iam_role.ml_admin.arn
}

output "ml_readonly_role_arn" {
  description = "ARN of the ML Readonly role"
  value       = aws_iam_role.ml_readonly.arn
}

# CI/CD Role — TODO: uncomment when Section 3 is enabled
# output "cicd_role_arn" {
#   description = "ARN of the CI/CD OIDC role (GitHub Actions)"
#   value       = aws_iam_role.cicd.arn
# }

# Groups
output "app_group_arn" {
  description = "ARN of the app IAM group"
  value       = aws_iam_group.app.arn
}

output "platform_group_arn" {
  description = "ARN of the platform IAM group"
  value       = aws_iam_group.platform.arn
}
