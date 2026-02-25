# =============================================================================
# Route 53 - Reference existing hosted zone
# (domain purchased via Route 53 → zone auto-created, no need to create)
# A alias records are created in environments/dev/main.tf
# (after CloudFront is provisioned to avoid circular dependency)
# =============================================================================

data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}
