# =============================================================================
# DynamoDB Tables
# =============================================================================

resource "aws_dynamodb_table" "surf_info" {
  name         = "${var.name}-surf-info"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "locationId"
  range_key    = "surfTimestamp"

  attribute {
    name = "locationId"
    type = "S"
  }

  attribute {
    name = "surfTimestamp"
    type = "S"
  }

  ttl {
    attribute_name = "expiredAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.name}-surf-info"
  }
}

resource "aws_dynamodb_table" "saved_list" {
  name         = "${var.name}-saved-list"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  range_key    = "SavedAt"

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "SavedAt"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.name}-saved-list"
  }
}
