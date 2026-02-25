output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = data.aws_route53_zone.this.zone_id
}
