# =============================================================================
# EKS Cluster
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.name
  cluster_version = "1.32"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Public access for kubectl (dev only)
  cluster_endpoint_public_access = true

  # Grant cluster creator (Terraform runner) admin access via access entries
  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  # IAM Role → EKS RBAC access entries (console + kubectl)
  access_entries = {
    infra_admin = {
      principal_arn = "arn:aws:iam::${var.account_id}:role/${var.name}-infra-admin-role"
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    infra_readonly = {
      principal_arn = "arn:aws:iam::${var.account_id}:role/${var.name}-infra-readonly-role"
      type          = "STANDARD"
      policy_associations = {
        view = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    app_readonly = {
      principal_arn = "arn:aws:iam::${var.account_id}:role/${var.name}-app-readonly-role"
      type          = "STANDARD"
      policy_associations = {
        view = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Managed node group
  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 3
      desired_size   = 3

      subnet_ids = var.private_subnet_ids
    }
  }

  tags = {
    Name = var.name
  }
}

# =============================================================================
# AWS Load Balancer Controller — IRSA
# =============================================================================

locals {
  oidc_issuer = trimprefix(module.eks.cluster_oidc_issuer_url, "https://")
}

resource "aws_iam_policy" "lb_controller" {
  name = "${var.name}-lb-controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs", "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags", "ec2:GetCoipPoolUsage", "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeListenerAttributes",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates", "acm:DescribeCertificate",
          "iam:ListServerCertificates", "iam:GetServerCertificate",
          "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState", "shield:DescribeProtection",
          "shield:CreateProtection", "shield:DeleteProtection",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType", "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets", "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
        ]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"]
          }
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule",
        ]
        Resource = "*"
      },
    ]
  })

  tags = { Name = "${var.name}-lb-controller" }
}

resource "aws_iam_role" "lb_controller" {
  name = "${var.name}-lb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.name}-lb-controller" }
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

# =============================================================================
# Backend API — IRSA
# =============================================================================

data "aws_region" "current" {}

resource "aws_iam_policy" "backend_api" {
  name = "${var.name}-backend-api"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${var.account_id}:table/${var.name}-*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::awaves-datalake-*",
          "arn:aws:s3:::awaves-datalake-*/*",
          "arn:aws:s3:::awaves-ml-*",
          "arn:aws:s3:::awaves-ml-*/*"
        ]
      },
      {
        Sid      = "SageMakerInvoke"
        Effect   = "Allow"
        Action   = ["sagemaker:InvokeEndpoint"]
        Resource = "arn:aws:sagemaker:${data.aws_region.current.name}:${var.account_id}:endpoint/${var.name}-*"
      },
      {
        Sid      = "OpenSearchAccess"
        Effect   = "Allow"
        Action   = ["es:ESHttp*"]
        Resource = "arn:aws:es:${data.aws_region.current.name}:${var.account_id}:domain/${var.name}-*"
      },
      {
        Sid      = "ElastiCacheConnect"
        Effect   = "Allow"
        Action   = ["elasticache:Connect"]
        Resource = "arn:aws:elasticache:${data.aws_region.current.name}:${var.account_id}:replicationgroup/${var.name}-*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${var.account_id}:log-group:/aws/eks/${var.name}/*"
      },
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        Sid      = "AuroraConnect"
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:${data.aws_region.current.name}:${var.account_id}:dbuser:*/*"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${var.account_id}:secret:${var.name}-*"
      }
    ]
  })

  tags = { Name = "${var.name}-backend-api" }
}

resource "aws_iam_role" "backend_api" {
  name = "${var.name}-backend-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.name}:backend-api"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.name}-backend-api" }
}

resource "aws_iam_role_policy_attachment" "backend_api" {
  role       = aws_iam_role.backend_api.name
  policy_arn = aws_iam_policy.backend_api.arn
}

resource "aws_iam_role_policy_attachment" "backend_api_xray" {
  role       = aws_iam_role.backend_api.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# =============================================================================
# Web App — IRSA
# =============================================================================

resource "aws_iam_policy" "web_app" {
  name = "${var.name}-web-app"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:GetDistribution",
          "cloudfront:ListDistributions"
        ]
        Resource = "*"
      },
      {
        Sid      = "SecretsManagerAccess"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${var.account_id}:secret:${var.name}-*"
      },
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${var.name}-web-app" }
}

resource "aws_iam_role" "web_app" {
  name = "${var.name}-web-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.name}:web-app"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.name}-web-app" }
}

resource "aws_iam_role_policy_attachment" "web_app" {
  role       = aws_iam_role.web_app.name
  policy_arn = aws_iam_policy.web_app.arn
}

# =============================================================================
# Mobile App — IRSA
# =============================================================================

resource "aws_iam_policy" "mobile_app" {
  name = "${var.name}-mobile-app"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SecretsManagerAccess"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${var.account_id}:secret:${var.name}-*"
      },
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = { Name = "${var.name}-mobile-app" }
}

resource "aws_iam_role" "mobile_app" {
  name = "${var.name}-mobile-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.name}:mobile-app"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.name}-mobile-app" }
}

resource "aws_iam_role_policy_attachment" "mobile_app" {
  role       = aws_iam_role.mobile_app.name
  policy_arn = aws_iam_policy.mobile_app.arn
}
