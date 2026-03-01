"""
Lambda: Drift Detection
Compute PSI on BatchTransform inference output vs. training baseline.
If isDrift=true, trigger SageMaker retraining pipeline (if configured).

Input event (injected by Step Functions Parameters):
  {
    "inference_s3_path": "s3://awaves-datalake-dev/inference/"
  }

Baseline (written once during SageMaker training pipeline evaluate step):
  s3://awaves-ml-{env}/drift/baseline.json
  { "rating_distribution": [0.05, 0.15, 0.35, 0.30, 0.15] }  # 5 bins: 0-4

Output:
  {
    "isDrift": false,
    "psi": 0.04,
    "threshold": 0.25,
    "inference_prefix": "inference/",
    "n_records": 216000
  }

PSI thresholds:
  < 0.10  : no significant drift
  0.10-0.25: moderate drift (warning)
  > 0.25  : significant drift → trigger retraining
"""

import csv
import io
import json
import math
import os
from datetime import datetime, timezone

import boto3

S3_BUCKET_ML = os.environ["S3_BUCKET_ML"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
# Optional: set to trigger SageMaker Pipeline on drift
SAGEMAKER_PIPELINE_ARN = os.environ.get("SAGEMAKER_PIPELINE_ARN", "")

s3 = boto3.client("s3")
sm = boto3.client("sagemaker") if SAGEMAKER_PIPELINE_ARN else None

N_BINS = 5  # rating bins: 0, 1, 2, 3, 4
PSI_THRESHOLD = 0.25
BASELINE_KEY = "drift/baseline.json"


def _parse_s3_uri(uri):
    """'s3://bucket/prefix/' -> ('bucket', 'prefix/')"""
    path = uri.replace("s3://", "")
    bucket, _, prefix = path.partition("/")
    return bucket, prefix


def _list_out_files(bucket, prefix):
    """List all .out files under prefix."""
    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".out"):
                keys.append(obj["Key"])
    return keys


def _compute_distribution(bucket, keys):
    """
    Read inference .out CSV files and compute rating distribution of y_pred_adv.
    Returns (counts list of length N_BINS, total n_records).
    """
    counts = [0] * N_BINS
    n_records = 0

    for key in keys:
        obj = s3.get_object(Bucket=bucket, Key=key)
        content = obj["Body"].read().decode("utf-8")
        reader = csv.DictReader(io.StringIO(content))
        for row in reader:
            raw = row.get("y_pred_adv")
            if raw is None:
                continue
            try:
                idx = min(N_BINS - 1, max(0, round(float(raw))))
                counts[idx] += 1
                n_records += 1
            except (ValueError, TypeError):
                continue

    return counts, n_records


def _normalize(counts):
    """Convert counts to proportions (avoids division by zero)."""
    total = sum(counts) or 1
    return [c / total for c in counts]


def _psi(baseline_pct, current_pct):
    """
    Standard PSI: Σ (actual% - expected%) * ln(actual% / expected%)
    """
    psi = 0.0
    for b, c in zip(baseline_pct, current_pct):
        b = max(b, 1e-4)
        c = max(c, 1e-4)
        psi += (c - b) * math.log(c / b)
    return psi


def handler(event, context):
    inference_s3_path = event.get("inference_s3_path", "")

    if not inference_s3_path:
        return {
            "isDrift": False,
            "reason": "no_inference_path",
            "message": "inference_s3_path not provided in event.",
        }

    inf_bucket, inf_prefix = _parse_s3_uri(inference_s3_path)

    # --- Load baseline distribution ---
    try:
        obj = s3.get_object(Bucket=S3_BUCKET_ML, Key=BASELINE_KEY)
        baseline = json.loads(obj["Body"].read().decode())
    except Exception:
        # No baseline yet → first run after training, skip drift check
        return {
            "isDrift": False,
            "reason": "no_baseline",
            "message": f"No baseline at s3://{S3_BUCKET_ML}/{BASELINE_KEY}. Skipping.",
            "inference_prefix": inf_prefix,
        }

    baseline_dist = baseline.get("rating_distribution", [])
    if len(baseline_dist) != N_BINS:
        return {
            "isDrift": False,
            "reason": "baseline_format_error",
            "message": f"baseline.rating_distribution must have {N_BINS} elements.",
            "inference_prefix": inf_prefix,
        }

    # --- Compute current distribution from .out files ---
    out_files = _list_out_files(inf_bucket, inf_prefix)
    if not out_files:
        return {
            "isDrift": False,
            "reason": "no_inference_files",
            "message": f"No .out files at {inference_s3_path}.",
            "inference_prefix": inf_prefix,
        }

    current_counts, n_records = _compute_distribution(inf_bucket, out_files)
    if n_records == 0:
        return {
            "isDrift": False,
            "reason": "empty_inference_output",
            "message": "All .out files had no valid y_pred_adv values.",
            "inference_prefix": inf_prefix,
        }

    current_dist = _normalize(current_counts)
    baseline_pct = _normalize(baseline_dist)

    psi = _psi(baseline_pct, current_dist)
    is_drift = psi > PSI_THRESHOLD

    # --- Save drift report to S3 (ML bucket) ---
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    report = {
        "timestamp": timestamp,
        "inference_s3_path": inference_s3_path,
        "n_records": n_records,
        "psi": round(psi, 6),
        "isDrift": is_drift,
        "threshold": PSI_THRESHOLD,
        "baseline_distribution": baseline_pct,
        "current_distribution": current_dist,
    }
    s3.put_object(
        Bucket=S3_BUCKET_ML,
        Key=f"drift/reports/{timestamp}.json",
        Body=json.dumps(report),
        ContentType="application/json",
    )

    # Derive processed_prefix from inference_s3_path:
    # "s3://awaves-datalake-dev/inference/2026/02/28/00/" -> "processed/2026/02/28/00/"
    processed_prefix = inf_prefix.replace("inference/", "processed/", 1)

    # --- Trigger retraining pipeline if drift detected ---
    if is_drift and SAGEMAKER_PIPELINE_ARN and sm:
        try:
            sm.start_pipeline_execution(
                PipelineArn=SAGEMAKER_PIPELINE_ARN,
                PipelineExecutionDisplayName=f"drift-retrain-{timestamp}",
                PipelineParameters=[
                    {"Name": "DriftPsi", "Value": str(round(psi, 4))},
                    {"Name": "ProcessedPrefix", "Value": processed_prefix},
                ],
            )
        except Exception as e:
            # Non-fatal: drift report already saved, pipeline trigger failed
            report["pipeline_trigger_error"] = str(e)

    return {
        "isDrift": is_drift,
        "psi": round(psi, 4),
        "threshold": PSI_THRESHOLD,
        "n_records": n_records,
        "inference_prefix": inf_prefix,
        "processed_prefix": processed_prefix,
    }
