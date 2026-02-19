output "distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "CloudFront distribution domain name (e.g. d1234.cloudfront.net)"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront hosted zone ID (for Route 53 alias)"
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}
