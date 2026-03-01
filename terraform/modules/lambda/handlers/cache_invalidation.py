"""
Lambda: Cache Invalidation
Triggered by EventBridge when a new hourly model is approved in SageMaker Model Registry.

1. Flush all awaves:surf:latest:* keys from ElastiCache Valkey.
2. Find the latest processed/ prefix in S3.
3. Trigger the batch-inference Step Functions (BatchTransform → SaveToDatabase)
   using the existing processed data — no API re-call needed.

Trigger:
  EventBridge rule:
    source: ["aws.sagemaker"]
    detail-type: ["SageMaker Model Package State Change"]
    detail.ModelApprovalStatus: ["Approved"]
    detail.ModelPackageGroupName: [<hourly-model-group>]

Input event (from EventBridge):
  {
    "source": "aws.sagemaker",
    "detail-type": "SageMaker Model Package State Change",
    "detail": {
      "ModelPackageGroupName": "awaves-hourly",
      "ModelApprovalStatus": "Approved",
      "ModelPackageArn": "arn:aws:sagemaker:..."
    }
  }

Output:
  { "deleted": 1045, "model_package_arn": "...", "pipeline_execution_arn": "..." }
"""

import json
import os

import boto3

ELASTICACHE_ENDPOINT = os.environ.get("ELASTICACHE_ENDPOINT", "")
INFERENCE_STATE_MACHINE_ARN = os.environ.get("INFERENCE_STATE_MACHINE_ARN", "")
S3_BUCKET = os.environ.get("S3_BUCKET_DATALAKE", "")
CACHE_KEY_PATTERN = "awaves:surf:latest:*"
SCAN_COUNT = 500

_redis_client = None
s3 = boto3.client("s3")
sfn = boto3.client("stepfunctions")


def _get_valkey():
    global _redis_client
    if _redis_client is None and ELASTICACHE_ENDPOINT:
        import valkey
        _redis_client = valkey.Valkey(
            host=ELASTICACHE_ENDPOINT,
            port=6379,
            ssl=True,
            ssl_cert_reqs=None,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=5,
        )
    return _redis_client


def _find_latest_processed_prefix():
    """List processed/ in S3 and return the most recently modified prefix (YYYY/MM/DD/HH/)."""
    paginator = s3.get_paginator("list_objects_v2")
    latest_key = None
    latest_modified = None

    for page in paginator.paginate(Bucket=S3_BUCKET, Prefix="processed/"):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            modified = obj["LastModified"]
            if latest_modified is None or modified > latest_modified:
                latest_modified = modified
                latest_key = key

    if not latest_key:
        return None, None

    # Extract prefix: processed/YYYY/MM/DD/HH/filename -> processed/YYYY/MM/DD/HH/
    parts = latest_key.split("/")  # ['processed', 'YYYY', 'MM', 'DD', 'HH', 'filename']
    if len(parts) < 5:
        return None, None

    processed_prefix = "/".join(parts[:5]) + "/"
    inference_prefix = processed_prefix.replace("processed/", "inference/", 1)
    return processed_prefix, inference_prefix


def handler(event, context):
    detail = event.get("detail", {})
    model_package_arn = detail.get("ModelPackageArn", "unknown")
    model_group = detail.get("ModelPackageGroupName", "unknown")

    print(f"[cache_invalidation] triggered by model_group={model_group} arn={model_package_arn}")

    # 1. Flush stale cache
    r = _get_valkey()
    deleted = 0
    if not r:
        print("[cache_invalidation] No ElastiCache endpoint configured, skipping cache flush.")
    else:
        cursor = 0
        while True:
            cursor, keys = r.scan(cursor=cursor, match=CACHE_KEY_PATTERN, count=SCAN_COUNT)
            if keys:
                pipe = r.pipeline()
                for key in keys:
                    pipe.unlink(key)
                pipe.execute()
                deleted += len(keys)
            if cursor == 0:
                break
        print(f"[cache_invalidation] deleted={deleted} keys matching '{CACHE_KEY_PATTERN}'")

    # 2. Find latest processed prefix and trigger inference-only pipeline
    pipeline_execution_arn = None
    if INFERENCE_STATE_MACHINE_ARN and S3_BUCKET:
        processed_prefix, inference_prefix = _find_latest_processed_prefix()
        if processed_prefix:
            print(f"[cache_invalidation] latest processed_prefix={processed_prefix}")
            try:
                model_version = model_package_arn.split("/")[-1] if model_package_arn != "unknown" else "unknown"
                resp = sfn.start_execution(
                    stateMachineArn=INFERENCE_STATE_MACHINE_ARN,
                    name=f"model-approved-{model_version}"[:80],
                    input=json.dumps({
                        "processed_prefix": processed_prefix,
                        "inference_prefix":  inference_prefix,
                        "trigger":           "model_approved",
                        "model_package_arn": model_package_arn,
                    }),
                )
                pipeline_execution_arn = resp["executionArn"]
                print(f"[cache_invalidation] batch-inference triggered: {pipeline_execution_arn}")
            except Exception as e:
                print(f"[cache_invalidation] Failed to trigger Step Functions: {e}")
        else:
            print("[cache_invalidation] No processed data found in S3, skipping inference trigger.")
    else:
        print("[cache_invalidation] INFERENCE_STATE_MACHINE_ARN or S3_BUCKET_DATALAKE not configured.")

    return {
        "deleted": deleted,
        "model_package_arn": model_package_arn,
        "pipeline_execution_arn": pipeline_execution_arn,
    }
