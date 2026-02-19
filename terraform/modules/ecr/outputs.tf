output "repository_web_app_url" {
  description = "ECR repository URL for web app"
  value       = aws_ecr_repository.web_app.repository_url
}

output "repository_mobile_app_url" {
  description = "ECR repository URL for mobile app"
  value       = aws_ecr_repository.mobile_app.repository_url
}

output "repository_backend_api_url" {
  description = "ECR repository URL for backend API"
  value       = aws_ecr_repository.backend_api.repository_url
}
