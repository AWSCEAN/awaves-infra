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
    enabled        = false
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.name}-surf-info"
  }
}

resource "aws_dynamodb_table" "locations" {
  name         = "${var.name}-locations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "locationId"

  attribute {
    name = "locationId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.name}-locations"
  }
}

resource "aws_dynamodb_table" "saved_list" {
  name         = "${var.name}-saved-list"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "sortKey"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "sortKey"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.name}-saved-list"
  }
}
