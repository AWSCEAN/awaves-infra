# =============================================================================
# Lambda Execution Role
# =============================================================================

resource "aws_iam_role" "lambda_execution" {
  name = "${var.name}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.name}-lambda-execution"
  }
}

# CloudWatch Logs (all Lambda functions need this)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# S3 access — Lambda reads/writes datalake bucket only
resource "aws_iam_policy" "lambda_s3_access" {
  name = "${var.name}-lambda-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = [
        "arn:aws:s3:::${var.bucket_datalake}",
        "arn:aws:s3:::${var.bucket_datalake}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_s3_access.arn
}

# DynamoDB access (Lambda: Save writes to tables)
resource "aws_iam_policy" "lambda_dynamodb_access" {
  name = "${var.name}-lambda-dynamodb-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:BatchWriteItem"
      ]
      Resource = [
        "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-surf-data",
        "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-saved-list"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_dynamodb_access.arn
}

# SNS publish (Lambda: Alert -> Discord)
resource "aws_iam_policy" "lambda_sns_publish" {
  name = "${var.name}-lambda-sns-publish"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = "arn:aws:sns:${var.aws_region}:${var.account_id}:${var.name}-*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sns" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_sns_publish.arn
}

# =============================================================================
# SageMaker Execution Role
# =============================================================================

resource "aws_iam_role" "sagemaker_execution" {
  name = "${var.name}-sagemaker-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "sagemaker.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.name}-sagemaker-execution"
  }
}

# S3 access — SageMaker reads datalake (processed/) and reads/writes ml bucket
resource "aws_iam_policy" "sagemaker_s3_access" {
  name = "${var.name}-sagemaker-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ]
      Resource = [
        "arn:aws:s3:::${var.bucket_datalake}",
        "arn:aws:s3:::${var.bucket_datalake}/*",
        "arn:aws:s3:::${var.bucket_ml}",
        "arn:aws:s3:::${var.bucket_ml}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_s3" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.sagemaker_s3_access.arn
}

# ECR access (pull training/inference images)
resource "aws_iam_policy" "sagemaker_ecr_access" {
  name = "${var.name}-sagemaker-ecr-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_ecr" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.sagemaker_ecr_access.arn
}

# CloudWatch Logs
resource "aws_iam_role_policy_attachment" "sagemaker_cloudwatch" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# SageMaker full access (for pipelines, endpoints, model registry)
resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# =============================================================================
# Developer Groups & Users
# =============================================================================

resource "aws_iam_group" "infra" {
  name = "${var.name}-infra"
}

resource "aws_iam_group" "dev" {
  name = "${var.name}-dev"
}

resource "aws_iam_user" "infra" {
  for_each = toset(var.infra_users)
  name     = each.value
  tags     = { Group = "${var.name}-infra" }
}

resource "aws_iam_user" "dev" {
  for_each = toset(var.dev_users)
  name     = each.value
  tags     = { Group = "${var.name}-dev" }
}

resource "aws_iam_group_membership" "infra" {
  name  = "${var.name}-infra-membership"
  group = aws_iam_group.infra.name
  users = [for u in aws_iam_user.infra : u.name]
}

resource "aws_iam_group_membership" "dev" {
  name  = "${var.name}-dev-membership"
  group = aws_iam_group.dev.name
  users = [for u in aws_iam_user.dev : u.name]
}

# --- infra group policies ---

resource "aws_iam_group_policy_attachment" "infra_sagemaker" {
  group      = aws_iam_group.infra.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_group_policy_attachment" "infra_lambda" {
  group      = aws_iam_group.infra.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
}

resource "aws_iam_group_policy_attachment" "infra_dynamodb" {
  group      = aws_iam_group.infra.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_group_policy_attachment" "infra_cloudwatch" {
  group      = aws_iam_group.infra.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_group_policy_attachment" "infra_eks" {
  group      = aws_iam_group.infra.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_policy" "infra_s3" {
  name = "${var.name}-infra-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = ["arn:aws:s3:::awaves-*", "arn:aws:s3:::awaves-*/*"]
    }]
  })
}

resource "aws_iam_group_policy_attachment" "infra_s3" {
  group      = aws_iam_group.infra.name
  policy_arn = aws_iam_policy.infra_s3.arn
}

resource "aws_iam_group_policy_attachment" "infra_bedrock" {
  group      = aws_iam_group.infra.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

# --- dev group policies ---

resource "aws_iam_policy" "dev_permissions" {
  name = "${var.name}-dev-permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      },
      {
        Sid      = "EKSRead"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks:ListClusters"]
        Resource = "*"
      },
      {
        Sid    = "FrontendS3"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::awaves-frontend-*",
          "arn:aws:s3:::awaves-frontend-*/*"
        ]
      },
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:GetLogEvents", "logs:FilterLogEvents", "logs:DescribeLogGroups"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "dev_permissions" {
  group      = aws_iam_group.dev.name
  policy_arn = aws_iam_policy.dev_permissions.arn
}

# =============================================================================
# Console Login Profiles (autogenerated passwords)
# =============================================================================

resource "aws_iam_user_login_profile" "infra" {
  for_each                = aws_iam_user.infra
  user                    = each.value.name
  password_reset_required = true
}

resource "aws_iam_user_login_profile" "dev" {
  for_each                = aws_iam_user.dev
  user                    = each.value.name
  password_reset_required = true
}
