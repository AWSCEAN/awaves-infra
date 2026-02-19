# =============================================================================
# CloudFront Distribution
# Origins:
#   - S3 (frontend static assets) — default behavior
#   - ALB (API /api/*) — forwarded behavior
# =============================================================================

locals {
  s3_origin_id  = "s3-frontend"
  alb_origin_id = "alb-api"
}

# OAC (Origin Access Control) — S3 private access
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.name}-frontend-oac"
  description                       = "OAC for awaves frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_200"  # NA + EU + Asia (excl. South America/Africa/Australia)
  web_acl_id          = var.waf_web_acl_arn != null ? var.waf_web_acl_arn : null
  aliases             = var.domain_name != "" ? [var.domain_name] : []

  # =============================================================================
  # Origin 1: S3 (Frontend static assets)
  # =============================================================================

  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # =============================================================================
  # Origin 2: ALB (Backend API — /api/*)
  # Conditional: only created after EKS Ingress provisions the ALB
  # =============================================================================

  dynamic "origin" {
    for_each = var.alb_dns_name != "" ? [1] : []
    content {
      domain_name = var.alb_dns_name
      origin_id   = local.alb_origin_id

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # =============================================================================
  # Default Behavior: S3 (SPA — serve index.html for all paths)
  # =============================================================================

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # SPA: 1 day cache for assets, 0 for index.html (handled by S3 metadata)
    default_ttl = 86400
    max_ttl     = 31536000
    min_ttl     = 0
  }

  # =============================================================================
  # Ordered Behavior: ALB (/api/*)
  # Conditional: only active when alb_dns_name is set
  # =============================================================================

  dynamic "ordered_cache_behavior" {
    for_each = var.alb_dns_name != "" ? [1] : []
    content {
      path_pattern           = "/api/*"
      target_origin_id       = local.alb_origin_id
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      forwarded_values {
        query_string = true
        headers      = ["Authorization", "Origin", "Accept", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
        cookies {
          forward = "all"
        }
      }

      # API: no cache
      default_ttl = 0
      max_ttl     = 0
      min_ttl     = 0
    }
  }

  # SPA fallback: 404 → index.html (client-side routing)
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 300
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != "" ? "TLSv1.2_2021" : "TLSv1"
  }

  tags = {
    Name = "${var.name}-cloudfront"
  }
}

# =============================================================================
# S3 Bucket Policy — allow CloudFront OAC only
# =============================================================================

data "aws_iam_policy_document" "s3_cloudfront" {
  statement {
    sid    = "AllowCloudFrontOAC"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${var.s3_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_cloudfront.json
}
