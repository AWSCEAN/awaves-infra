# =============================================================================
# DynamoDB Tables
# =============================================================================

resource "aws_dynamodb_table" "surf_data" {
  name         = "${var.name}-surf-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LocationId"
  range_key    = "SurfTimestamp"

  attribute {
    name = "LocationId"
    type = "S"
  }

  attribute {
    name = "SurfTimestamp"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.name}-surf-data"
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
