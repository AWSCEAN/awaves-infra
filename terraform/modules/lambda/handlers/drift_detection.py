"""
Lambda: Drift Detection
Compare recent prediction distributions against baseline to detect model drift.
Triggered after SageMaker Batch Transform completes.

Input event:
  {
    "inference_date": "2026-02-15",
    "model_version": "v1"
  }

Output:
  Returns: { "isDrift": true/false, "metrics": {...} }
  If isDrift=true, triggers SageMaker retraining pipeline.
"""

import json
import os

import boto3

S3_BUCKET = os.environ.get("S3_BUCKET", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

s3 = boto3.client("s3")


def _load_json_from_s3(bucket, key):
    """Load JSON from S3."""
    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        return json.loads(obj["Body"].read().decode())
    except Exception:
        return None


def _calculate_psi(baseline_dist, current_dist):
    """
    Calculate Population Stability Index (PSI).
    PSI < 0.1: no drift
    PSI 0.1-0.25: moderate drift
    PSI > 0.25: significant drift
    """
    psi = 0.0
    for i in range(len(baseline_dist)):
        b = max(baseline_dist[i], 0.0001)
        c = max(current_dist[i], 0.0001)
        psi += (c - b) * (c / b if b > 0 else 0)
    return psi


def handler(event, context):
    inference_date = event.get("inference_date", "")
    model_version = event.get("model_version", "v1")

    # Load baseline distribution (set during training)
    baseline_key = f"drift/baseline/{model_version}/distribution.json"
    baseline = _load_json_from_s3(S3_BUCKET, baseline_key)

    if not baseline:
        return {
            "isDrift": False,
            "reason": "no_baseline",
            "message": f"No baseline found at {baseline_key}. Skipping drift check.",
        }

    # Load current inference results distribution
    current_key = f"inference/{inference_date}/distribution.json"
    current = _load_json_from_s3(S3_BUCKET, current_key)

    if not current:
        return {
            "isDrift": False,
            "reason": "no_current_data",
            "message": f"No current data found at {current_key}.",
        }

    # Calculate PSI for rating distribution
    baseline_dist = baseline.get("rating_distribution", [])
    current_dist = current.get("rating_distribution", [])

    if len(baseline_dist) != len(current_dist):
        return {
            "isDrift": False,
            "reason": "distribution_mismatch",
            "message": "Baseline and current distributions have different lengths.",
        }

    psi = _calculate_psi(baseline_dist, current_dist)
    is_drift = psi > 0.25

    # Save drift report
    report = {
        "date": inference_date,
        "model_version": model_version,
        "psi": psi,
        "isDrift": is_drift,
        "threshold": 0.25,
        "baseline_dist": baseline_dist,
        "current_dist": current_dist,
    }

    s3.put_object(
        Bucket=S3_BUCKET,
        Key=f"drift/reports/{inference_date}.json",
        Body=json.dumps(report),
        ContentType="application/json",
    )

    return {
        "isDrift": is_drift,
        "psi": round(psi, 4),
        "threshold": 0.25,
        "model_version": model_version,
        "date": inference_date,
    }
