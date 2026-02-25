"""
Lambda: Cache Invalidation
Triggered by EventBridge when a new hourly model is approved in SageMaker Model Registry.
Flushes all awaves:surf:latest:* keys from ElastiCache Valkey.

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
  { "deleted": 1045, "model_package_arn": "arn:aws:sagemaker:..." }
"""

import os

ELASTICACHE_ENDPOINT = os.environ.get("ELASTICACHE_ENDPOINT", "")
CACHE_KEY_PATTERN = "awaves:surf:latest:*"
SCAN_COUNT = 500

_redis_client = None


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


def handler(event, context):
    detail = event.get("detail", {})
    model_package_arn = detail.get("ModelPackageArn", "unknown")
    model_group = detail.get("ModelPackageGroupName", "unknown")

    print(f"[cache_invalidation] triggered by model_group={model_group} arn={model_package_arn}")

    r = _get_valkey()
    if not r:
        print("[cache_invalidation] No ElastiCache endpoint configured, skipping.")
        return {"deleted": 0, "model_package_arn": model_package_arn}

    deleted = 0
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
    return {"deleted": deleted, "model_package_arn": model_package_arn}
