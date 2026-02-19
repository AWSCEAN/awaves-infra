output "bucket_datalake" {
  description = "Datalake S3 bucket name (raw, processed, inference, spots)"
  value       = aws_s3_bucket.datalake.id
}

output "bucket_ml" {
  description = "ML S3 bucket name (training, models, pipeline, drift)"
  value       = aws_s3_bucket.ml.id
}

output "bucket_frontend" {
  description = "Frontend S3 bucket name (CloudFront Origin)"
  value       = aws_s3_bucket.frontend.id
}

output "bucket_frontend_arn" {
  description = "Frontend S3 bucket ARN"
  value       = aws_s3_bucket.frontend.arn
}

output "bucket_frontend_regional_domain_name" {
  description = "Frontend S3 bucket regional domain name (for CloudFront OAC)"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "bucket_logs" {
  description = "Logs S3 bucket name (CloudFront, ALB, S3 access logs)"
  value       = aws_s3_bucket.logs.id
}
