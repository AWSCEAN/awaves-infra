# =============================================================================
# Step Functions - Data Collection Pipeline
# =============================================================================

resource "aws_iam_role" "step_functions" {
  name = "${var.name}-step-functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.name}-step-functions"
  }
}

resource "aws_iam_role_policy" "step_functions_invoke_lambda" {
  name = "${var.name}-invoke-lambda"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          var.lambda_api_call_arn,
          var.lambda_preprocessing_arn,
          var.lambda_drift_detection_arn,
          var.lambda_save_arn,
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTransformJob",
          "sagemaker:DescribeTransformJob",
          "sagemaker:StopTransformJob",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = var.sagemaker_execution_role_arn
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutTargets",
          "events:PutRule",
          "events:DescribeRule",
          "events:DeleteRule",
          "events:RemoveTargets"
        ]
        Resource = "arn:aws:events:*:*:rule/StepFunctionsGetEventsFor*"
      },
    ]
  })
}

resource "aws_sfn_state_machine" "data_collection" {
  name     = "${var.name}-data-collection"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "awaves data collection pipeline"
    StartAt = "ApiCall"
    States = {
      ApiCall = {
        Type     = "Task"
        Resource = var.lambda_api_call_arn
        Comment  = "Fetch data from external APIs (Surfline, Open-Meteo)"
        Next     = "Preprocessing"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      Preprocessing = {
        Type     = "Task"
        Resource = var.lambda_preprocessing_arn
        Comment  = "Transform raw data and save to S3 processed"
        Next     = "BatchTransform"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      BatchTransform = {
        Type     = "Task"
        Resource = "arn:aws:states:::sagemaker:createTransformJob.sync"
        Comment  = "Run SageMaker Batch Transform: processed data -> surf index predictions"
        Parameters = {
          "TransformJobName.$" = "States.Format('bt-{}', $$.Execution.Name)"
          ModelName            = "${var.name}-surf-index"
          TransformInput = {
            DataSource = {
              S3DataSource = {
                S3DataType = "S3Prefix"
                S3Uri      = "s3://${var.s3_bucket_datalake}/processed/"
              }
            }
            ContentType     = "text/csv"
            SplitType       = "Line"
          }
          TransformOutput = {
            S3OutputPath = "s3://${var.s3_bucket_datalake}/inference/"
          }
          TransformResources = {
            InstanceCount = 1
            InstanceType  = "ml.m5.large"
          }
        }
        Next = "DriftDetection"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 60
          MaxAttempts     = 1
          BackoffRate     = 1.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      DriftDetection = {
        Type     = "Task"
        Resource = var.lambda_drift_detection_arn
        Comment  = "Compute PSI on inference output; trigger retraining if isDrift=true"
        Parameters = {
          inference_s3_path = "s3://${var.s3_bucket_datalake}/inference/"
        }
        Next = "SaveToDatabase"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      SaveToDatabase = {
        Type     = "Task"
        Resource = var.lambda_save_arn
        Comment  = "Persist processed data to DynamoDB"
        Next     = "PipelineSucceeded"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 10
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "PipelineFailed"
        }]
      }
      PipelineSucceeded = {
        Type = "Succeed"
      }
      PipelineFailed = {
        Type  = "Fail"
        Error = "PipelineError"
        Cause = "Data collection pipeline failed"
      }
    }
  })

  tags = {
    Name = "${var.name}-data-collection"
  }
}
