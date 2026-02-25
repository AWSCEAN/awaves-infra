# =============================================================================
# SageMaker Security Group (VPC mode — self-referencing rule required)
# =============================================================================

resource "aws_security_group" "domain" {
  name        = "${var.name}-sagemaker-domain"
  description = "SageMaker domain (VPC mode) - intra-cluster communication"
  vpc_id      = var.vpc_id

  # SageMaker VPC mode requires self-referencing ingress
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sagemaker-domain"
  }
}

# =============================================================================
# SageMaker Domain (Studio — VPC-only mode)
# Note: Creates an EFS file system (~$0.30/GB/month) for Studio storage
# =============================================================================

resource "aws_sagemaker_domain" "this" {
  domain_name             = var.name
  auth_mode               = "IAM"
  vpc_id                  = var.vpc_id
  subnet_ids              = var.private_subnet_ids
  app_network_access_type = "VpcOnly"

  default_user_settings {
    execution_role  = var.sagemaker_execution_role_arn
    security_groups = [aws_security_group.domain.id]
  }

  domain_settings {
    execution_role_identity_config = "USER_PROFILE_NAME"
  }

  tags = {
    Name = var.name
  }
}

# =============================================================================
# Model Package Group (Model Registry)
# Versioned model registry: surf-index models (XGBoost / LightGBM)
# Model 1 ... Model N — managed by SageMaker Pipelines evaluation step
# =============================================================================

resource "aws_sagemaker_model_package_group" "surf_index" {
  model_package_group_name        = "${var.name}-surf-index"
  model_package_group_description = "awaves surf index model registry (XGBoost / LightGBM)"

  tags = {
    Name = "${var.name}-surf-index"
  }
}

# =============================================================================
# S3: Upload pipeline scripts (preprocess.py, evaluate.py)
# SageMaker Processing Jobs download these at runtime.
# =============================================================================

resource "aws_s3_object" "preprocess_script" {
  bucket = var.s3_bucket_ml
  key    = "pipeline/scripts/preprocess.py"
  source = "${path.module}/scripts/preprocess.py"
  etag   = filemd5("${path.module}/scripts/preprocess.py")
}

resource "aws_s3_object" "evaluate_script" {
  bucket = var.s3_bucket_ml
  key    = "pipeline/scripts/evaluate.py"
  source = "${path.module}/scripts/evaluate.py"
  etag   = filemd5("${path.module}/scripts/evaluate.py")
}

# =============================================================================
# SageMaker AI Training Pipeline
#
# Flow:
#   Preprocessing (Processing Job - sklearn)
#   -> Training (Training Job - XGBoost built-in)
#   -> Evaluation (Processing Job - sklearn: metrics + drift baseline)
#   -> EvaluationCondition (QWK >= threshold?)
#      |- True  -> RegisterModel (Model Registry, Approved)
#      |- False -> AlertDataScientists (Lambda: alert-ml-pipeline)
#
# Triggered by: Lambda drift_detection when isDrift=true
# Input data  : s3://{s3_bucket_ml}/training/  (uploaded by data team)
# =============================================================================

locals {
  # SageMaker built-in container URIs for us-east-1
  sklearn_image  = "683313688378.dkr.ecr.${var.aws_region}.amazonaws.com/sagemaker-scikit-learn:1.2-1-cpu-py3"
  xgboost_image  = "683313688378.dkr.ecr.${var.aws_region}.amazonaws.com/sagemaker-xgboost:1.7-1"

  # S3 paths (deterministic — preprocessing always writes here)
  scripts_uri    = "s3://${var.s3_bucket_ml}/pipeline/scripts/"
  train_input_uri = "s3://${var.s3_bucket_ml}/training/"
  train_out_uri  = "s3://${var.s3_bucket_ml}/pipeline/processed/train/"
  val_out_uri    = "s3://${var.s3_bucket_ml}/pipeline/processed/validation/"
  model_out_uri  = "s3://${var.s3_bucket_ml}/models/"
  eval_out_uri   = "s3://${var.s3_bucket_ml}/pipeline/evaluation/"
  drift_out_uri  = "s3://${var.s3_bucket_ml}/drift/"
}

resource "aws_sagemaker_pipeline" "training" {
  pipeline_name         = "${var.name}-training"
  pipeline_display_name = "${var.name}-training"
  pipeline_description  = "awaves surf index training pipeline: Preprocess -> XGBoost -> Evaluate -> Register/Alert"
  role_arn              = var.sagemaker_execution_role_arn

  pipeline_definition = jsonencode({
    Version = "2020-12-01"

    Parameters = [
      { Name = "DriftPsi", Type = "String", DefaultValue = "0.0" },
    ]

    Steps = [

      # -----------------------------------------------------------------------
      # Step 1: Preprocessing
      # sklearn Processing Job: parquet -> feature engineering -> train/val CSVs
      # -----------------------------------------------------------------------
      {
        Name = "Preprocessing"
        Type = "Processing"
        Arguments = {
          AppSpecification = {
            ImageUri            = local.sklearn_image
            ContainerEntrypoint = ["python3", "/opt/ml/processing/input/code/preprocess.py"]
          }
          ProcessingInputs = [
            {
              InputName  = "code"
              AppManaged = false
              S3Input = {
                S3Uri       = local.scripts_uri
                LocalPath   = "/opt/ml/processing/input/code"
                S3DataType  = "S3Prefix"
                S3InputMode = "File"
              }
            },
            {
              InputName  = "data"
              AppManaged = false
              S3Input = {
                S3Uri       = local.train_input_uri
                LocalPath   = "/opt/ml/processing/input/data"
                S3DataType  = "S3Prefix"
                S3InputMode = "File"
              }
            },
          ]
          ProcessingOutputConfig = {
            Outputs = [
              {
                OutputName = "train"
                AppManaged = false
                S3Output = {
                  S3Uri        = local.train_out_uri
                  LocalPath    = "/opt/ml/processing/output/train"
                  S3UploadMode = "EndOfJob"
                }
              },
              {
                OutputName = "validation"
                AppManaged = false
                S3Output = {
                  S3Uri        = local.val_out_uri
                  LocalPath    = "/opt/ml/processing/output/validation"
                  S3UploadMode = "EndOfJob"
                }
              },
            ]
          }
          ProcessingResources = {
            ClusterConfig = {
              InstanceCount  = 1
              InstanceType   = "ml.m5.large"
              VolumeSizeInGB = 30
            }
          }
          StoppingCondition = { MaxRuntimeInSeconds = 3600 }
          RoleArn           = var.sagemaker_execution_role_arn
        }
      },

      # -----------------------------------------------------------------------
      # Step 2: Training
      # XGBoost built-in algorithm: multi-class classification (5 classes)
      # -----------------------------------------------------------------------
      {
        Name      = "Training"
        Type      = "Training"
        DependsOn = ["Preprocessing"]
        Arguments = {
          AlgorithmSpecification = {
            TrainingImage     = local.xgboost_image
            TrainingInputMode = "File"
          }
          InputDataConfig = [
            {
              ChannelName = "train"
              DataSource = {
                S3DataSource = {
                  S3Uri                  = local.train_out_uri
                  S3DataType             = "S3Prefix"
                  S3DataDistributionType = "FullyReplicated"
                }
              }
              ContentType = "text/csv"
              InputMode   = "File"
            },
            {
              ChannelName = "validation"
              DataSource = {
                S3DataSource = {
                  S3Uri                  = local.val_out_uri
                  S3DataType             = "S3Prefix"
                  S3DataDistributionType = "FullyReplicated"
                }
              }
              ContentType = "text/csv"
              InputMode   = "File"
            },
          ]
          OutputDataConfig = {
            S3OutputPath = local.model_out_uri
          }
          ResourceConfig = {
            InstanceCount  = 1
            InstanceType   = "ml.m5.xlarge"
            VolumeSizeInGB = 30
          }
          HyperParameters = {
            num_round          = "300"
            objective          = "multi:softmax"
            num_class          = "5"
            max_depth          = "6"
            eta                = "0.1"
            subsample          = "0.8"
            colsample_bytree   = "0.8"
            eval_metric        = "merror"
            early_stopping_rounds = "20"
          }
          StoppingCondition = { MaxRuntimeInSeconds = 7200 }
          RoleArn           = var.sagemaker_execution_role_arn
        }
      },

      # -----------------------------------------------------------------------
      # Step 3: Evaluation
      # sklearn Processing Job: compute QWK/accuracy + write drift baseline
      # Outputs a PropertyFile so the Condition step can read metrics.qwk
      # -----------------------------------------------------------------------
      {
        Name      = "Evaluation"
        Type      = "Processing"
        DependsOn = ["Training"]
        Arguments = {
          AppSpecification = {
            ImageUri            = local.sklearn_image
            ContainerEntrypoint = ["python3", "/opt/ml/processing/input/code/evaluate.py"]
          }
          ProcessingInputs = [
            {
              InputName  = "code"
              AppManaged = false
              S3Input = {
                S3Uri       = local.scripts_uri
                LocalPath   = "/opt/ml/processing/input/code"
                S3DataType  = "S3Prefix"
                S3InputMode = "File"
              }
            },
            {
              InputName  = "model"
              AppManaged = false
              S3Input = {
                # Reference training step model artifact (dynamic)
                S3Uri       = { "Get" = "Steps.Training.ModelArtifacts.S3ModelArtifacts" }
                LocalPath   = "/opt/ml/processing/input/model"
                S3DataType  = "S3Prefix"
                S3InputMode = "File"
              }
            },
            {
              InputName  = "validation"
              AppManaged = false
              S3Input = {
                S3Uri       = local.val_out_uri
                LocalPath   = "/opt/ml/processing/input/validation"
                S3DataType  = "S3Prefix"
                S3InputMode = "File"
              }
            },
          ]
          ProcessingOutputConfig = {
            Outputs = [
              {
                OutputName = "evaluation"
                AppManaged = false
                S3Output = {
                  S3Uri        = local.eval_out_uri
                  LocalPath    = "/opt/ml/processing/output/evaluation"
                  S3UploadMode = "EndOfJob"
                }
              },
              {
                OutputName = "drift-baseline"
                AppManaged = false
                S3Output = {
                  # Overwrites drift/baseline.json each training run
                  S3Uri        = local.drift_out_uri
                  LocalPath    = "/opt/ml/processing/output/drift"
                  S3UploadMode = "EndOfJob"
                }
              },
            ]
          }
          ProcessingResources = {
            ClusterConfig = {
              InstanceCount  = 1
              InstanceType   = "ml.m5.large"
              VolumeSizeInGB = 20
            }
          }
          StoppingCondition = { MaxRuntimeInSeconds = 1800 }
          RoleArn           = var.sagemaker_execution_role_arn
        }
        PropertyFiles = [
          {
            PropertyFileName = "EvaluationReport"
            OutputName       = "evaluation"
            FilePath         = "evaluation.json"
          }
        ]
      },

      # -----------------------------------------------------------------------
      # Step 4: Condition — QWK >= threshold?
      # True  -> RegisterModel (Model Registry, Approved)
      # False -> AlertDataScientists (Lambda)
      # -----------------------------------------------------------------------
      {
        Name      = "EvaluationCondition"
        Type      = "Condition"
        DependsOn = ["Evaluation"]
        Arguments = {
          Conditions = [
            {
              Type = "GreaterThanOrEqualTo"
              LeftValue = {
                "Std:JsonGet" = {
                  PropertyFile = { "Get" = "Steps.Evaluation.PropertyFiles.EvaluationReport" }
                  Path         = "metrics.qwk"
                }
              }
              RightValue = var.qwk_threshold
            }
          ]

          # True branch: register approved model in Model Registry
          IfSteps = [
            {
              Name = "RegisterModel"
              Type = "RegisterModel"
              Arguments = {
                ModelPackageGroupName = aws_sagemaker_model_package_group.surf_index.model_package_group_name
                ModelApprovalStatus   = "Approved"
                InferenceSpecification = {
                  Containers = [
                    {
                      Image        = local.xgboost_image
                      ModelDataUrl = { "Get" = "Steps.Training.ModelArtifacts.S3ModelArtifacts" }
                    }
                  ]
                  SupportedContentTypes      = ["text/csv"]
                  SupportedResponseMIMETypes = ["text/csv"]
                }
              }
            }
          ]

          # False branch: alert data scientists via SNS
          ElseSteps = [
            {
              Name        = "AlertDataScientists"
              Type        = "Lambda"
              FunctionArn = var.lambda_alert_ml_pipeline_arn
              Arguments = {
                evaluation_result = "bad"
                threshold         = tostring(var.qwk_threshold)
              }
            }
          ]
        }
      },
    ]
  })

  tags = {
    Name = "${var.name}-training"
  }

  depends_on = [
    aws_s3_object.preprocess_script,
    aws_s3_object.evaluate_script,
  ]
}

# =============================================================================
# SageMaker Real-time Endpoint (Flow 2: historical / on-demand inference)
#
# Lifecycle:
#   1. Training pipeline registers an Approved model in Model Registry
#   2. Set var.model_data_url = "s3://{bucket}/models/{job}/output/model.tar.gz"
#   3. terraform apply  ->  Model + EndpointConfig + Endpoint are created/updated
#
# Endpoint name: {name}-surf-index  (e.g. awaves-dev-surf-index)
# Instance type: ml.t3.medium  (~$0.05/hr, sufficient for dev inference)
# =============================================================================

resource "aws_sagemaker_model" "surf_index" {
  count              = var.model_data_url != "" ? 1 : 0
  name               = "${var.name}-surf-index"
  execution_role_arn = var.sagemaker_execution_role_arn

  primary_container {
    image          = local.xgboost_image
    model_data_url = var.model_data_url
  }

  tags = {
    Name = "${var.name}-surf-index"
  }
}

resource "aws_sagemaker_endpoint_configuration" "surf_index" {
  count = var.model_data_url != "" ? 1 : 0
  name  = "${var.name}-surf-index"

  production_variants {
    variant_name           = "primary"
    model_name             = aws_sagemaker_model.surf_index[0].name
    initial_instance_count = 1
    instance_type          = "ml.t3.medium"
    initial_variant_weight = 1
  }

  tags = {
    Name = "${var.name}-surf-index"
  }
}

resource "aws_sagemaker_endpoint" "surf_index" {
  count                = var.model_data_url != "" ? 1 : 0
  name                 = "${var.name}-surf-index"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.surf_index[0].name

  tags = {
    Name = "${var.name}-surf-index"
  }
}
