# =============================================================================
# Deployment packages (one zip per handler)
# =============================================================================

data "archive_file" "api_call" {
  type        = "zip"
  source_file = "${path.module}/handlers/api_call.py"
  output_path = "${path.module}/handlers/api_call.zip"
}

data "archive_file" "preprocessing" {
  type        = "zip"
  source_file = "${path.module}/handlers/preprocessing.py"
  output_path = "${path.module}/handlers/preprocessing.zip"
}

data "archive_file" "save" {
  type        = "zip"
  source_file = "${path.module}/handlers/save.py"
  output_path = "${path.module}/handlers/save.zip"
}

data "archive_file" "drift_detection" {
  type        = "zip"
  source_file = "${path.module}/handlers/drift_detection.py"
  output_path = "${path.module}/handlers/drift_detection.zip"
}

data "archive_file" "alert_monitoring" {
  type        = "zip"
  source_file = "${path.module}/handlers/alert_monitoring.py"
  output_path = "${path.module}/handlers/alert_monitoring.zip"
}

data "archive_file" "alert_ml_pipeline" {
  type        = "zip"
  source_file = "${path.module}/handlers/alert_ml_pipeline.py"
  output_path = "${path.module}/handlers/alert_ml_pipeline.zip"
}

# =============================================================================
# Lambda Functions
# =============================================================================

# 1. API Call - fetch data from external APIs (Open-Meteo Marine + Weather)
resource "aws_lambda_function" "api_call" {
  function_name = "${var.name}-api-call"
  role          = var.lambda_execution_role_arn
  handler       = "api_call.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 256

  filename         = data.archive_file.api_call.output_path
  source_code_hash = data.archive_file.api_call.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      S3_BUCKET_DATALAKE = var.s3_bucket_datalake
    }
  }

  tags = {
    Name = "${var.name}-api-call"
  }
}

# 2. Preprocessing - merge marine + weather, flatten hourly data
resource "aws_lambda_function" "preprocessing" {
  function_name = "${var.name}-preprocessing"
  role          = var.lambda_execution_role_arn
  handler       = "preprocessing.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.preprocessing.output_path
  source_code_hash = data.archive_file.preprocessing.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      S3_BUCKET_DATALAKE = var.s3_bucket_datalake
    }
  }

  tags = {
    Name = "${var.name}-preprocessing"
  }
}

# 3. Save - persist processed data to DynamoDB
resource "aws_lambda_function" "save" {
  function_name = "${var.name}-save"
  role          = var.lambda_execution_role_arn
  handler       = "save.handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 256

  filename         = data.archive_file.save.output_path
  source_code_hash = data.archive_file.save.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      S3_BUCKET_DATALAKE = var.s3_bucket_datalake
      DYNAMODB_TABLE     = var.dynamodb_table_surf_data
    }
  }

  tags = {
    Name = "${var.name}-save"
  }
}

# 4. Drift Detection - monitor model drift via PSI
resource "aws_lambda_function" "drift_detection" {
  function_name = "${var.name}-drift-detection"
  role          = var.lambda_execution_role_arn
  handler       = "drift_detection.handler"
  runtime       = "python3.12"
  timeout       = 120
  memory_size   = 256

  filename         = data.archive_file.drift_detection.output_path
  source_code_hash = data.archive_file.drift_detection.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT  = var.environment
      S3_BUCKET_ML = var.s3_bucket_ml
    }
  }

  tags = {
    Name = "${var.name}-drift-detection"
  }
}

# 5. Alert Monitoring - SNS -> Discord webhook
resource "aws_lambda_function" "alert_monitoring" {
  function_name = "${var.name}-alert-monitoring"
  role          = var.lambda_execution_role_arn
  handler       = "alert_monitoring.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.alert_monitoring.output_path
  source_code_hash = data.archive_file.alert_monitoring.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
    }
  }

  tags = {
    Name = "${var.name}-alert-monitoring"
  }
}

# SNS subscription for alert_monitoring
resource "aws_sns_topic_subscription" "alert_monitoring" {
  topic_arn = var.sns_alerts_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.alert_monitoring.arn
}

resource "aws_lambda_permission" "sns_alert_monitoring" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alert_monitoring.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_alerts_topic_arn
}

# 6. Alert ML Pipeline - notify data scientists on bad evaluation
resource "aws_lambda_function" "alert_ml_pipeline" {
  function_name = "${var.name}-alert-ml-pipeline"
  role          = var.lambda_execution_role_arn
  handler       = "alert_ml_pipeline.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.alert_ml_pipeline.output_path
  source_code_hash = data.archive_file.alert_ml_pipeline.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT   = var.environment
      SNS_TOPIC_ARN = var.sns_alerts_topic_arn
    }
  }

  tags = {
    Name = "${var.name}-alert-ml-pipeline"
  }
}
