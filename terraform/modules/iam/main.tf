# =============================================================================
# Section 1: Service Execution Roles
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Execution Role
# -----------------------------------------------------------------------------

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for Lambda VPC config (ENI creation for ElastiCache access)
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy" "lambda_s3_access" {
  name = "${var.name}-lambda-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DatalakeBucketAccess"
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
      },
      {
        # drift_detection Lambda: read baseline.json, write drift reports
        Sid    = "MLBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_ml}",
          "arn:aws:s3:::${var.bucket_ml}/*"
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_s3_access.arn
}

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
        "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-surf-info",
        "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-saved-list"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_dynamodb_access.arn
}

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

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_policy" "lambda_bedrock_access" {
  name = "${var.name}-lambda-bedrock-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BedrockInvokeModel"
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = [
        "arn:aws:bedrock:us-east-1::foundation-model/us.anthropic.claude-3-5-haiku-20241022-v1:0"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_bedrock" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_bedrock_access.arn
}

resource "aws_iam_policy" "lambda_sagemaker_pipeline" {
  name = "${var.name}-lambda-sagemaker-pipeline"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # drift_detection Lambda: trigger retraining pipeline when isDrift=true
      Sid    = "SageMakerPipelineTrigger"
      Effect = "Allow"
      Action = [
        "sagemaker:StartPipelineExecution",
        "sagemaker:DescribePipelineExecution",
        "sagemaker:ListPipelineExecutions",
      ]
      Resource = "arn:aws:sagemaker:${var.aws_region}:${var.account_id}:pipeline/${var.name}-training"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sagemaker_pipeline" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_sagemaker_pipeline.arn
}

# -----------------------------------------------------------------------------
# SageMaker Execution Role
# -----------------------------------------------------------------------------

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

resource "aws_iam_role_policy_attachment" "sagemaker_cloudwatch" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_policy" "sagemaker_lambda_invoke" {
  name = "${var.name}-sagemaker-lambda-invoke"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LambdaInvokeForPipeline"
      Effect = "Allow"
      Action = [
        "lambda:InvokeFunction",
        "lambda:GetFunction",
      ]
      Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.name}-*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_lambda_invoke" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = aws_iam_policy.sagemaker_lambda_invoke.arn
}

# =============================================================================
# Section 2: Human Roles (RBAC)
# Trust: account root — any principal with sts:AssumeRole permission can assume
# =============================================================================

locals {
  human_role_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.account_id}:root"
      }
    }]
  })
}

# -----------------------------------------------------------------------------
# App Admin Role
# Target: Lambda, StepFunctions, EventBridge, ECR(app repos), CloudWatch, DynamoDB
# -----------------------------------------------------------------------------

resource "aws_iam_role" "app_admin" {
  name               = "${var.name}-app-admin-role"
  assume_role_policy = local.human_role_trust
  tags               = { Name = "${var.name}-app-admin-role", Domain = "app" }
}

resource "aws_iam_policy" "app_admin" {
  name = "${var.name}-app-admin-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAccess"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:DeleteFunction",
          "lambda:InvokeFunction",
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:GetPolicy",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:PublishVersion",
          "lambda:CreateAlias",
          "lambda:UpdateAlias",
          "lambda:DeleteAlias",
          "lambda:ListVersionsByFunction",
          "lambda:ListAliases",
          "lambda:TagResource",
          "lambda:UntagResource"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.name}-*"
      },
      {
        Sid    = "StepFunctionsAccess"
        Effect = "Allow"
        Action = [
          "states:CreateStateMachine",
          "states:UpdateStateMachine",
          "states:DeleteStateMachine",
          "states:StartExecution",
          "states:StopExecution",
          "states:ListStateMachines",
          "states:DescribeStateMachine",
          "states:ListExecutions",
          "states:DescribeExecution",
          "states:GetExecutionHistory",
          "states:TagResource",
          "states:UntagResource"
        ]
        Resource = "arn:aws:states:${var.aws_region}:${var.account_id}:stateMachine:${var.name}-*"
      },
      {
        Sid    = "EventBridgeAccess"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:PutTargets",
          "events:DeleteRule",
          "events:RemoveTargets",
          "events:EnableRule",
          "events:DisableRule",
          "events:ListRules",
          "events:DescribeRule",
          "events:ListTargetsByRule",
          "scheduler:CreateSchedule",
          "scheduler:UpdateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:ListSchedules",
          "scheduler:GetSchedule"
        ]
        Resource = "*"
      },
      {
        Sid      = "ECRFullAccess"
        Effect   = "Allow"
        Action   = ["ecr:*"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:DeleteLogGroup"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${var.name}-*"
      },
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_admin" {
  role       = aws_iam_role.app_admin.name
  policy_arn = aws_iam_policy.app_admin.arn
}

resource "aws_iam_role_policy_attachment" "app_admin_cloudwatch" {
  role       = aws_iam_role.app_admin.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# -----------------------------------------------------------------------------
# App Readonly Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "app_readonly" {
  name               = "${var.name}-app-readonly-role"
  assume_role_policy = local.human_role_trust
  tags               = { Name = "${var.name}-app-readonly-role", Domain = "app" }
}

resource "aws_iam_policy" "app_readonly" {
  name = "${var.name}-app-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaList"
        Effect   = "Allow"
        Action   = ["lambda:ListFunctions", "lambda:ListVersionsByFunction", "lambda:ListAliases"]
        Resource = "*"
      },
      {
        Sid      = "LambdaRead"
        Effect   = "Allow"
        Action   = ["lambda:GetFunction", "lambda:GetPolicy"]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.name}-*"
      },
      {
        Sid      = "StepFunctionsList"
        Effect   = "Allow"
        Action   = ["states:ListStateMachines"]
        Resource = "*"
      },
      {
        Sid    = "StepFunctionsRead"
        Effect = "Allow"
        Action = [
          "states:DescribeStateMachine",
          "states:ListExecutions",
          "states:DescribeExecution",
          "states:GetExecutionHistory"
        ]
        Resource = "arn:aws:states:${var.aws_region}:${var.account_id}:stateMachine:${var.name}-*"
      },
      {
        Sid    = "EventBridgeRead"
        Effect = "Allow"
        Action = [
          "events:ListRules",
          "events:DescribeRule",
          "events:ListTargetsByRule",
          "scheduler:ListSchedules",
          "scheduler:GetSchedule"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-*"
      },
      {
        Sid      = "DynamoDBListRead"
        Effect   = "Allow"
        Action   = ["dynamodb:ListTables"]
        Resource = "*"
      },
      {
        Sid      = "VPCRead"
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]
        Resource = "*"
      },
      {
        Sid    = "EKSRead"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster", "eks:ListClusters",
          "eks:DescribeNodegroup", "eks:ListNodegroups",
          "eks:DescribeAddon", "eks:ListAddons"
        ]
        Resource = "*"
      },
      {
        Sid      = "RDSRead"
        Effect   = "Allow"
        Action   = ["rds:Describe*", "rds:List*"]
        Resource = "*"
      },
      {
        Sid      = "ElastiCacheRead"
        Effect   = "Allow"
        Action   = ["elasticache:Describe*", "elasticache:List*"]
        Resource = "*"
      },
      {
        Sid      = "S3ListAllBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:ListBucket",
          "s3:GetBucketLocation", "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${var.name}-*",
          "arn:aws:s3:::${var.name}-*/*"
        ]
      },
      {
        Sid      = "SageMakerRead"
        Effect   = "Allow"
        Action   = ["sagemaker:Describe*", "sagemaker:List*"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetricsRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSRead"
        Effect = "Allow"
        Action = [
          "sns:ListTopics", "sns:GetTopicAttributes",
          "sns:ListSubscriptions"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFrontRead"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:ListDistributions",
          "cloudfront:GetDistributionConfig"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53Read"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones", "route53:ListResourceRecordSets",
          "route53:GetHostedZone", "route53:ListHealthChecks",
          "route53:GetHealthCheck"
        ]
        Resource = "*"
      },
      {
        Sid      = "KMSRead"
        Effect   = "Allow"
        Action   = ["kms:ListKeys", "kms:DescribeKey", "kms:ListAliases"]
        Resource = "*"
      },
      {
        Sid    = "IAMRead"
        Effect = "Allow"
        Action = [
          "iam:ListRoles", "iam:ListUsers", "iam:ListGroups",
          "iam:ListPolicies", "iam:GetRole", "iam:GetPolicy",
          "iam:GetPolicyVersion", "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies", "iam:GetRolePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_readonly" {
  role       = aws_iam_role.app_readonly.name
  policy_arn = aws_iam_policy.app_readonly.arn
}

# -----------------------------------------------------------------------------
# Infra Admin Role
# Target: VPC, EKS, RDS, ElastiCache, S3, Route53, IAM(PassRole only)
# -----------------------------------------------------------------------------

resource "aws_iam_role" "infra_admin" {
  name               = "${var.name}-infra-admin-role"
  assume_role_policy = local.human_role_trust
  tags               = { Name = "${var.name}-infra-admin-role", Domain = "infra" }
}

resource "aws_iam_policy" "infra_admin" {
  name = "${var.name}-infra-admin-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:DeleteNatGateway",
          "ec2:AllocateAddress",
          "ec2:ReleaseAddress",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateVpcEndpoint",
          "ec2:DeleteVpcEndpoints",
          "ec2:ModifyVpcEndpoint",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:CreateCluster",
          "eks:DeleteCluster",
          "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion",
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:CreateNodegroup",
          "eks:DeleteNodegroup",
          "eks:UpdateNodegroupConfig",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:CreateAddon",
          "eks:DeleteAddon",
          "eks:UpdateAddon",
          "eks:DescribeAddon",
          "eks:ListAddons",
          "eks:TagResource",
          "eks:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "RDSAccess"
        Effect = "Allow"
        Action = [
          "rds:CreateDBCluster",
          "rds:DeleteDBCluster",
          "rds:ModifyDBCluster",
          "rds:CreateDBInstance",
          "rds:DeleteDBInstance",
          "rds:ModifyDBInstance",
          "rds:RebootDBInstance",
          "rds:Describe*",
          "rds:List*",
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:CreateDBParameterGroup",
          "rds:DeleteDBParameterGroup",
          "rds:CreateDBClusterParameterGroup",
          "rds:DeleteDBClusterParameterGroup",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "ElastiCacheAccess"
        Effect = "Allow"
        Action = [
          "elasticache:CreateReplicationGroup",
          "elasticache:DeleteReplicationGroup",
          "elasticache:ModifyReplicationGroup",
          "elasticache:CreateCacheSubnetGroup",
          "elasticache:DeleteCacheSubnetGroup",
          "elasticache:CreateCacheParameterGroup",
          "elasticache:DeleteCacheParameterGroup",
          "elasticache:Describe*",
          "elasticache:List*",
          "elasticache:AddTagsToResource",
          "elasticache:RemoveTagsFromResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.name}-*",
          "arn:aws:s3:::${var.name}-*/*"
        ]
      },
      {
        Sid    = "Route53Access"
        Effect = "Allow"
        Action = [
          "route53:CreateHostedZone",
          "route53:DeleteHostedZone",
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
          "route53:CreateHealthCheck",
          "route53:DeleteHealthCheck",
          "route53:UpdateHealthCheck",
          "route53:GetHealthCheck",
          "route53:ListHealthChecks"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMPassRoleOnly"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.lambda_execution.arn,
          aws_iam_role.sagemaker_execution.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_admin" {
  role       = aws_iam_role.infra_admin.name
  policy_arn = aws_iam_policy.infra_admin.arn
}

# -----------------------------------------------------------------------------
# Infra Readonly Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "infra_readonly" {
  name               = "${var.name}-infra-readonly-role"
  assume_role_policy = local.human_role_trust
  tags               = { Name = "${var.name}-infra-readonly-role", Domain = "infra" }
}

resource "aws_iam_policy" "infra_readonly" {
  name = "${var.name}-infra-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "VPCRead"
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]
        Resource = "*"
      },
      {
        Sid    = "EKSRead"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DescribeAddon",
          "eks:ListAddons"
        ]
        Resource = "*"
      },
      {
        Sid      = "RDSRead"
        Effect   = "Allow"
        Action   = ["rds:Describe*", "rds:List*"]
        Resource = "*"
      },
      {
        Sid      = "ElastiCacheRead"
        Effect   = "Allow"
        Action   = ["elasticache:Describe*", "elasticache:List*"]
        Resource = "*"
      },
      {
        Sid      = "S3ListAllBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:GetBucketVersioning"]
        Resource = [
          "arn:aws:s3:::${var.name}-*",
          "arn:aws:s3:::${var.name}-*/*"
        ]
      },
      {
        Sid    = "Route53Read"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListHealthChecks",
          "route53:GetHealthCheck"
        ]
        Resource = "*"
      },
      {
        Sid      = "LambdaList"
        Effect   = "Allow"
        Action   = ["lambda:ListFunctions", "lambda:ListVersionsByFunction", "lambda:ListAliases"]
        Resource = "*"
      },
      {
        Sid      = "LambdaRead"
        Effect   = "Allow"
        Action   = ["lambda:GetFunction", "lambda:GetPolicy"]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.name}-*"
      },
      {
        Sid      = "StepFunctionsList"
        Effect   = "Allow"
        Action   = ["states:ListStateMachines"]
        Resource = "*"
      },
      {
        Sid    = "StepFunctionsRead"
        Effect = "Allow"
        Action = [
          "states:DescribeStateMachine",
          "states:ListExecutions", "states:DescribeExecution",
          "states:GetExecutionHistory"
        ]
        Resource = "arn:aws:states:${var.aws_region}:${var.account_id}:stateMachine:${var.name}-*"
      },
      {
        Sid    = "EventBridgeRead"
        Effect = "Allow"
        Action = [
          "events:ListRules", "events:DescribeRule",
          "events:ListTargetsByRule",
          "scheduler:ListSchedules", "scheduler:GetSchedule"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages", "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      },
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:Query",
          "dynamodb:Scan", "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-*"
      },
      {
        Sid      = "DynamoDBListRead"
        Effect   = "Allow"
        Action   = ["dynamodb:ListTables"]
        Resource = "*"
      },
      {
        Sid      = "SageMakerRead"
        Effect   = "Allow"
        Action   = ["sagemaker:Describe*", "sagemaker:List*"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
          "logs:GetLogEvents", "logs:FilterLogEvents",
          "logs:DescribeLogGroups", "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSRead"
        Effect = "Allow"
        Action = [
          "sns:ListTopics", "sns:GetTopicAttributes",
          "sns:ListSubscriptions"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFrontRead"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:ListDistributions",
          "cloudfront:GetDistributionConfig"
        ]
        Resource = "*"
      },
      {
        Sid      = "KMSRead"
        Effect   = "Allow"
        Action   = ["kms:ListKeys", "kms:DescribeKey", "kms:ListAliases"]
        Resource = "*"
      },
      {
        Sid    = "IAMRead"
        Effect = "Allow"
        Action = [
          "iam:ListRoles", "iam:ListUsers", "iam:ListGroups",
          "iam:ListPolicies", "iam:GetRole", "iam:GetPolicy",
          "iam:GetPolicyVersion", "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies", "iam:GetRolePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "infra_readonly" {
  role       = aws_iam_role.infra_readonly.name
  policy_arn = aws_iam_policy.infra_readonly.arn
}

# -----------------------------------------------------------------------------
# ML Admin Role
# Target: SageMaker, S3(ML/datalake buckets), ECR(pull), CloudWatch
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ml_admin" {
  name               = "${var.name}-ml-admin-role"
  assume_role_policy = local.human_role_trust
  tags               = { Name = "${var.name}-ml-admin-role", Domain = "ml" }
}

resource "aws_iam_policy" "ml_admin" {
  name = "${var.name}-ml-admin-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerAccess"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTrainingJob",
          "sagemaker:StopTrainingJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:ListTrainingJobs",
          "sagemaker:CreateTransformJob",
          "sagemaker:StopTransformJob",
          "sagemaker:DescribeTransformJob",
          "sagemaker:ListTransformJobs",
          "sagemaker:CreateModel",
          "sagemaker:DeleteModel",
          "sagemaker:DescribeModel",
          "sagemaker:ListModels",
          "sagemaker:CreateEndpoint",
          "sagemaker:DeleteEndpoint",
          "sagemaker:UpdateEndpoint",
          "sagemaker:DescribeEndpoint",
          "sagemaker:ListEndpoints",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:DeleteEndpointConfig",
          "sagemaker:DescribeEndpointConfig",
          "sagemaker:ListEndpointConfigs",
          "sagemaker:CreatePipeline",
          "sagemaker:DeletePipeline",
          "sagemaker:UpdatePipeline",
          "sagemaker:DescribePipeline",
          "sagemaker:ListPipelines",
          "sagemaker:StartPipelineExecution",
          "sagemaker:StopPipelineExecution",
          "sagemaker:DescribePipelineExecution",
          "sagemaker:ListPipelineExecutions",
          "sagemaker:CreateModelPackage",
          "sagemaker:UpdateModelPackage",
          "sagemaker:DescribeModelPackage",
          "sagemaker:ListModelPackages",
          "sagemaker:CreateModelPackageGroup",
          "sagemaker:DeleteModelPackageGroup",
          "sagemaker:DescribeModelPackageGroup",
          "sagemaker:ListModelPackageGroups",
          "sagemaker:CreateDomain",
          "sagemaker:DeleteDomain",
          "sagemaker:DescribeDomain",
          "sagemaker:ListDomains",
          "sagemaker:AddTags",
          "sagemaker:DeleteTags",
          "sagemaker:ListTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3MLAccess"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.name}-data-*",
          "arn:aws:s3:::${var.name}-data-*/*",
          "arn:aws:s3:::${var.name}-sagemaker-*",
          "arn:aws:s3:::${var.name}-sagemaker-*/*"
        ]
      },
      {
        Sid    = "ECRPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid      = "IAMPassRoleML"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.sagemaker_execution.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ml_admin" {
  role       = aws_iam_role.ml_admin.name
  policy_arn = aws_iam_policy.ml_admin.arn
}

resource "aws_iam_role_policy_attachment" "ml_admin_bedrock" {
  role       = aws_iam_role.ml_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
}

# -----------------------------------------------------------------------------
# ML Readonly Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ml_readonly" {
  name               = "${var.name}-ml-readonly-role"
  assume_role_policy = local.human_role_trust
  tags               = { Name = "${var.name}-ml-readonly-role", Domain = "ml" }
}

resource "aws_iam_policy" "ml_readonly" {
  name = "${var.name}-ml-readonly-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerRead"
        Effect = "Allow"
        Action = [
          "sagemaker:Describe*",
          "sagemaker:List*"
        ]
        Resource = "*"
      },
      {
        Sid      = "S3ListAllBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        Sid    = "S3MLRead"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          "arn:aws:s3:::${var.name}-data-*",
          "arn:aws:s3:::${var.name}-data-*/*",
          "arn:aws:s3:::${var.name}-sagemaker-*",
          "arn:aws:s3:::${var.name}-sagemaker-*/*"
        ]
      },
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms",
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid      = "VPCRead"
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]
        Resource = "*"
      },
      {
        Sid    = "EKSRead"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster", "eks:ListClusters",
          "eks:DescribeNodegroup", "eks:ListNodegroups",
          "eks:DescribeAddon", "eks:ListAddons"
        ]
        Resource = "*"
      },
      {
        Sid      = "RDSRead"
        Effect   = "Allow"
        Action   = ["rds:Describe*", "rds:List*"]
        Resource = "*"
      },
      {
        Sid      = "ElastiCacheRead"
        Effect   = "Allow"
        Action   = ["elasticache:Describe*", "elasticache:List*"]
        Resource = "*"
      },
      {
        Sid    = "S3AllRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:ListBucket",
          "s3:GetBucketLocation", "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${var.name}-*",
          "arn:aws:s3:::${var.name}-*/*"
        ]
      },
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:Query",
          "dynamodb:Scan", "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.account_id}:table/${var.name}-*"
      },
      {
        Sid      = "DynamoDBListRead"
        Effect   = "Allow"
        Action   = ["dynamodb:ListTables"]
        Resource = "*"
      },
      {
        Sid      = "LambdaList"
        Effect   = "Allow"
        Action   = ["lambda:ListFunctions", "lambda:ListVersionsByFunction", "lambda:ListAliases"]
        Resource = "*"
      },
      {
        Sid      = "LambdaRead"
        Effect   = "Allow"
        Action   = ["lambda:GetFunction", "lambda:GetPolicy"]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.name}-*"
      },
      {
        Sid      = "StepFunctionsList"
        Effect   = "Allow"
        Action   = ["states:ListStateMachines"]
        Resource = "*"
      },
      {
        Sid    = "StepFunctionsRead"
        Effect = "Allow"
        Action = [
          "states:DescribeStateMachine",
          "states:ListExecutions", "states:DescribeExecution",
          "states:GetExecutionHistory"
        ]
        Resource = "arn:aws:states:${var.aws_region}:${var.account_id}:stateMachine:${var.name}-*"
      },
      {
        Sid    = "EventBridgeRead"
        Effect = "Allow"
        Action = [
          "events:ListRules", "events:DescribeRule",
          "events:ListTargetsByRule",
          "scheduler:ListSchedules", "scheduler:GetSchedule"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRead"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages", "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSRead"
        Effect = "Allow"
        Action = [
          "sns:ListTopics", "sns:GetTopicAttributes",
          "sns:ListSubscriptions"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFrontRead"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:ListDistributions",
          "cloudfront:GetDistributionConfig"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53Read"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones", "route53:ListResourceRecordSets",
          "route53:GetHostedZone", "route53:ListHealthChecks",
          "route53:GetHealthCheck"
        ]
        Resource = "*"
      },
      {
        Sid      = "KMSRead"
        Effect   = "Allow"
        Action   = ["kms:ListKeys", "kms:DescribeKey", "kms:ListAliases"]
        Resource = "*"
      },
      {
        Sid    = "IAMRead"
        Effect = "Allow"
        Action = [
          "iam:ListRoles", "iam:ListUsers", "iam:ListGroups",
          "iam:ListPolicies", "iam:GetRole", "iam:GetPolicy",
          "iam:GetPolicyVersion", "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies", "iam:GetRolePolicy"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ml_readonly" {
  role       = aws_iam_role.ml_readonly.name
  policy_arn = aws_iam_policy.ml_readonly.arn
}

# =============================================================================
# Section 3: CI/CD OIDC Role (GitHub Actions)
# =============================================================================

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "cicd" {
  name = "${var.name}-cicd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = resource.aws_iam_openid_connect_provider.github.arn
      }
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.name}-cicd-role" }
}

resource "aws_iam_policy" "cicd" {
  name = "${var.name}-cicd-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.name}-web-app",
          "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.name}-mobile-app",
          "arn:aws:ecr:${var.aws_region}:${var.account_id}:repository/${var.name}-backend-api"
        ]
      },
      {
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.aws_region}:${var.account_id}:cluster/${var.name}-*"
      },
      {
        Sid    = "S3FrontendDeploy"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.name}-frontend-*",
          "arn:aws:s3:::${var.name}-frontend-*/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cicd" {
  role       = aws_iam_role.cicd.name
  policy_arn = aws_iam_policy.cicd.arn
}

# =============================================================================
# Section 4: Groups (AssumeRole 정책만 보유)
# =============================================================================

resource "aws_iam_group" "app" {
  name = "${var.name}-app"
}

resource "aws_iam_group" "platform" {
  name = "${var.name}-platform"
}

# App 그룹: app-admin + infra-readonly + ml-readonly assume 가능
resource "aws_iam_group_policy" "app_assume_roles" {
  name  = "${var.name}-app-assume-roles"
  group = aws_iam_group.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = [
        aws_iam_role.app_admin.arn,
        aws_iam_role.infra_readonly.arn,
        aws_iam_role.ml_readonly.arn
      ]
    }]
  })
}

# Platform 그룹: infra-admin + ml-admin + app-readonly assume 가능
resource "aws_iam_group_policy" "platform_assume_roles" {
  name  = "${var.name}-platform-assume-roles"
  group = aws_iam_group.platform.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = [
        aws_iam_role.infra_admin.arn,
        aws_iam_role.ml_admin.arn,
        aws_iam_role.app_readonly.arn
      ]
    }]
  })
}

# =============================================================================
# Section 5: IAM Users
# =============================================================================

resource "aws_iam_user" "app" {
  for_each = toset(var.app_users)
  name     = each.value
  tags     = { Group = "${var.name}-app" }
}

resource "aws_iam_user" "platform" {
  for_each = toset(var.platform_users)
  name     = each.value
  tags     = { Group = "${var.name}-platform" }
}

resource "aws_iam_group_membership" "app" {
  name  = "${var.name}-app-membership"
  group = aws_iam_group.app.name
  users = [for u in aws_iam_user.app : u.name]
}

resource "aws_iam_group_membership" "platform" {
  name  = "${var.name}-platform-membership"
  group = aws_iam_group.platform.name
  users = [for u in aws_iam_user.platform : u.name]
}

resource "aws_iam_user_login_profile" "app" {
  for_each                = toset(var.app_users)
  user                    = each.value
  password_reset_required = true

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_iam_user_login_profile" "platform" {
  for_each                = toset(var.platform_users)
  user                    = each.value
  password_reset_required = true

  lifecycle {
    ignore_changes = all
  }
}

# =============================================================================
# Section 6: AdministratorAccess for all users (both groups)
# =============================================================================

resource "aws_iam_group_policy_attachment" "app_admin_access" {
  group      = aws_iam_group.app.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group_policy_attachment" "platform_admin_access" {
  group      = aws_iam_group.platform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
