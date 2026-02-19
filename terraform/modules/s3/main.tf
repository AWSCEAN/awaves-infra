data "aws_caller_identity" "current" {}

# =============================================================================
# S3 Buckets
# awaves-datalake-{env}  : raw (JSON), processed (Parquet), inference, spots
# awaves-ml-{env}        : training, models, pipeline, drift
# awaves-frontend-{env}  : CloudFront Origin
# awaves-logs-{env}      : CloudFront / ALB / S3 access logs
# =============================================================================

resource "aws_s3_bucket" "datalake" {
  bucket = "${var.project}-datalake-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project}-datalake-${var.environment}"
  }
}

resource "aws_s3_bucket" "ml" {
  bucket = "${var.project}-ml-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project}-ml-${var.environment}"
  }
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project}-frontend-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project}-frontend-${var.environment}"
  }
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.project}-logs-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project}-logs-${var.environment}"
  }
}

# =============================================================================
# Versioning (datalake, ml only)
# =============================================================================

resource "aws_s3_bucket_versioning" "datalake" {
  bucket = aws_s3_bucket.datalake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "ml" {
  bucket = aws_s3_bucket.ml.id
  versioning_configuration {
    status = "Enabled"
  }
}

# =============================================================================
# Server-Side Encryption (SSE-S3, free)
# =============================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ml" {
  bucket = aws_s3_bucket.ml.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =============================================================================
# Block Public Access
# =============================================================================

resource "aws_s3_bucket_public_access_block" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "ml" {
  bucket = aws_s3_bucket.ml.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# Lifecycle Policy — datalake
#
# raw/forecast/       : 30d → S3-IA, 90d → Glacier
# raw/rating/forecast/: 30d → S3-IA, 90d → Glacier
# raw/historical/     : permanent (no expiration)
# processed/forecast/ : 14d → delete  (추론 완료 후 불필요)
# inference/          : 30d → delete  (DynamoDB에 이미 저장)
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id

  rule {
    id     = "raw-forecast-tiering"
    status = "Enabled"
    filter {
      prefix = "raw/forecast/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "raw-rating-forecast-tiering"
    status = "Enabled"
    filter {
      prefix = "raw/rating/forecast/"
    }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "processed-forecast-expiry"
    status = "Enabled"
    filter {
      prefix = "processed/forecast/"
    }
    expiration {
      days = 14
    }
  }

  rule {
    id     = "inference-expiry"
    status = "Enabled"
    filter {
      prefix = "inference/"
    }
    expiration {
      days = 30
    }
  }
}

# =============================================================================
# Lifecycle Policy — logs
#
# 전체: 90d → delete
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "logs-expiry"
    status = "Enabled"
    filter {
      prefix = ""
    }
    expiration {
      days = 90
    }
  }
}
