# =============================================================================
# EventBridge - Scheduled Data Collection (every 3 hours)
# =============================================================================

resource "aws_iam_role" "eventbridge" {
  name = "${var.name}-eventbridge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.name}-eventbridge"
  }
}

resource "aws_iam_role_policy" "eventbridge_start_sfn" {
  name = "${var.name}-start-sfn"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "states:StartExecution"
      Resource = var.state_machine_arn
    }]
  })
}

resource "aws_scheduler_schedule" "data_collection" {
  name       = "${var.name}-data-collection"
  group_name = "default"

  schedule_expression          = "rate(3 hours)"
  schedule_expression_timezone = "Asia/Seoul"
  state                        = "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.state_machine_arn
    role_arn = aws_iam_role.eventbridge.arn
  }

  description = "Trigger data collection pipeline every 3 hours (DISABLED by default)"
}
