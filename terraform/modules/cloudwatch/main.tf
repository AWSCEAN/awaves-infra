# =============================================================================
# CloudWatch Log Groups
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda_api_call" {
  name              = "/aws/lambda/${var.name}-api-call"
  retention_in_days = 14
  tags              = { Name = "${var.name}-lambda-api-call" }
}

resource "aws_cloudwatch_log_group" "lambda_preprocessing" {
  name              = "/aws/lambda/${var.name}-preprocessing"
  retention_in_days = 14
  tags              = { Name = "${var.name}-lambda-preprocessing" }
}

resource "aws_cloudwatch_log_group" "lambda_save" {
  name              = "/aws/lambda/${var.name}-save"
  retention_in_days = 14
  tags              = { Name = "${var.name}-lambda-save" }
}

resource "aws_cloudwatch_log_group" "lambda_drift_detection" {
  name              = "/aws/lambda/${var.name}-drift-detection"
  retention_in_days = 14
  tags              = { Name = "${var.name}-lambda-drift-detection" }
}

resource "aws_cloudwatch_log_group" "lambda_alert_monitoring" {
  name              = "/aws/lambda/${var.name}-alert-monitoring"
  retention_in_days = 14
  tags              = { Name = "${var.name}-lambda-alert-monitoring" }
}

resource "aws_cloudwatch_log_group" "lambda_alert_ml_pipeline" {
  name              = "/aws/lambda/${var.name}-alert-ml-pipeline"
  retention_in_days = 14
  tags              = { Name = "${var.name}-lambda-alert-ml-pipeline" }
}

resource "aws_cloudwatch_log_group" "sagemaker" {
  name              = "/aws/sagemaker/${var.name}"
  retention_in_days = 30
  tags              = { Name = "${var.name}-sagemaker" }
}

resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/states/${var.name}-data-collection"
  retention_in_days = 14
  tags              = { Name = "${var.name}-step-functions" }
}

# =============================================================================
# CloudWatch Alarms
# =============================================================================

# Lambda: API Call — Error rate alarm
resource "aws_cloudwatch_metric_alarm" "lambda_api_call_errors" {
  alarm_name          = "${var.name}-lambda-api-call-errors"
  alarm_description   = "Lambda API Call error rate too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 3

  dimensions = {
    FunctionName = "${var.name}-api-call"
  }

  alarm_actions = [var.sns_alerts_topic_arn]
  ok_actions    = [var.sns_alerts_topic_arn]

  tags = { Name = "${var.name}-lambda-api-call-errors" }
}

# Step Functions: Execution failure alarm
resource "aws_cloudwatch_metric_alarm" "sfn_failed" {
  alarm_name          = "${var.name}-sfn-execution-failed"
  alarm_description   = "Step Functions data collection pipeline failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0

  dimensions = {
    StateMachineArn = var.step_functions_state_machine_arn
  }

  alarm_actions = [var.sns_alerts_topic_arn]

  tags = { Name = "${var.name}-sfn-failed" }
}

# DynamoDB: System errors alarm
resource "aws_cloudwatch_metric_alarm" "dynamodb_system_errors" {
  alarm_name          = "${var.name}-dynamodb-system-errors"
  alarm_description   = "DynamoDB system errors detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 5

  alarm_actions = [var.sns_alerts_topic_arn]

  tags = { Name = "${var.name}-dynamodb-system-errors" }
}

# =============================================================================
# CloudWatch Dashboard
# =============================================================================

resource "aws_cloudwatch_dashboard" "awaves" {
  dashboard_name = "${var.name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Invocations & Errors"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name}-api-call"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name}-api-call"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name}-preprocessing"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name}-preprocessing"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.name}-save"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.name}-save"],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Step Functions Executions"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", var.step_functions_state_machine_arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.step_functions_state_machine_arn],
            ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.step_functions_state_machine_arn],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB Requests"
          region = var.aws_region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "${var.name}-surf-data"],
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "${var.name}-surf-data"],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Duration (P95)"
          region = var.aws_region
          period = 300
          stat   = "p95"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.name}-api-call"],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.name}-preprocessing"],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.name}-save"],
          ]
        }
      }
    ]
  })
}
