"""
Lambda: Data Collection for Training

SageMaker Pipeline Lambda Step (Step 0) — invoked when drift is detected.

Reads processed CSVs from the datalake bucket (already feature-engineered,
23 coastline-relative features) and joins with pre-fetched Surfline ratings
stored in S3 (ratings/surfline_ratings_latest.csv) to create labeled training
data, then saves to the ML bucket.

Note: Surfline API blocks AWS Lambda IPs (HTTP 403). Ratings must be
pre-collected from a non-AWS machine and uploaded to:
  s3://{ML_BUCKET}/ratings/surfline_ratings_latest.csv

Ratings CSV format:
  spot_id, timestamp (unix int), rating_value (float)

Input (SageMaker Pipeline passes pipeline parameters as Lambda event):
  { "ProcessedPrefix": "processed/2026/02/28/00/" }

Output (SageMaker Lambda step OutputParameters):
  {
    "OutputParameters": [
      {"Name": "TrainingS3Uri", "Value": "s3://awaves-ml-dev/training/labeled_20260228000000.csv"}
    ]
  }

Training CSV format:
  rating_value (0-4 integer), feature1, feature2, ..., feature23
  (with header — SageMaker preprocess.py will strip it)
"""

import csv
import io
import os
from datetime import datetime, timezone

import boto3

S3_BUCKET_DATALAKE = os.environ["S3_BUCKET_DATALAKE"]
S3_BUCKET_ML = os.environ["S3_BUCKET_ML"]

RATINGS_S3_KEY = "ratings/surfline_ratings_latest.csv"

s3 = boto3.client("s3")

# Must match Lambda preprocessing handler FEATURE_COLS exactly
FEATURE_COLS = [
    "wave_height", "wave_period",
    "swell_wave_height", "swell_wave_period",
    "sea_surface_temperature",
    "wind_speed_10m", "wind_gusts_10m",
    "wave_direction_rel_sin", "wave_direction_rel_cos",
    "swell_wave_direction_rel_sin", "swell_wave_direction_rel_cos",
    "wind_direction_10m_rel_cos",
    "wave_power", "swell_power",
    "wind_wave_ratio", "wave_steepness",
    "abs_lat",
    "wind_onshore", "wind_cross", "gust_onshore",
    "wave_shore_power", "swell_shore_power", "swell_cross_power",
]


def _list_csvs(prefix):
    """List all CSV files under prefix in the datalake bucket."""
    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=S3_BUCKET_DATALAKE, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".csv"):
                keys.append(obj["Key"])
    return keys


def _read_processed_csvs(keys):
    """
    Read processed CSVs and return records list of {spot_id, datetime, feature1, ...}.
    Skips rows without valid Surfline spot_id or datetime.
    """
    records = []
    for key in keys:
        obj = s3.get_object(Bucket=S3_BUCKET_DATALAKE, Key=key)
        content = obj["Body"].read().decode("utf-8")
        reader = csv.DictReader(io.StringIO(content))
        for row in reader:
            spot_id = (row.get("spot_id") or "").strip()
            dt_str = (row.get("datetime") or "").strip()
            if not spot_id or not dt_str or spot_id in ("None", "none", ""):
                continue
            rec = {"spot_id": spot_id, "datetime": dt_str}
            for col in FEATURE_COLS:
                rec[col] = row.get(col, "")
            records.append(rec)
    return records


def _load_ratings_from_s3():
    """
    Load pre-fetched Surfline ratings from S3.
    Returns dict: (spot_id, unix_ts) -> rating_value (float).

    Ratings CSV columns: spot_id, timestamp, rating_value
    """
    print(f"[DataCollection] Loading ratings from s3://{S3_BUCKET_ML}/{RATINGS_S3_KEY}")
    obj = s3.get_object(Bucket=S3_BUCKET_ML, Key=RATINGS_S3_KEY)
    content = obj["Body"].read().decode("utf-8")
    reader = csv.DictReader(io.StringIO(content))
    ratings = {}
    for row in reader:
        spot_id = (row.get("spot_id") or "").strip()
        ts_str = (row.get("timestamp") or "").strip()
        val_str = (row.get("rating_value") or "").strip()
        if not spot_id or not ts_str or not val_str:
            continue
        try:
            ratings[(spot_id, int(float(ts_str)))] = float(val_str)
        except (ValueError, TypeError):
            continue
    return ratings


def _dt_to_unix(dt_str):
    """
    Convert ISO datetime string (e.g. "2026-02-28T00:00") to UTC unix timestamp.
    Returns None on parse error.
    """
    try:
        dt = datetime.fromisoformat(dt_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except (ValueError, TypeError):
        return None


def handler(event, context):
    processed_prefix = event.get("ProcessedPrefix", "").strip()
    if not processed_prefix:
        raise ValueError("ProcessedPrefix not provided in event")

    print(f"[DataCollection] Reading s3://{S3_BUCKET_DATALAKE}/{processed_prefix}")

    # ---- 1. Read processed CSVs ----------------------------------------
    csv_keys = _list_csvs(processed_prefix)
    if not csv_keys:
        raise FileNotFoundError(f"No CSV files at s3://{S3_BUCKET_DATALAKE}/{processed_prefix}")

    print(f"[DataCollection] Found {len(csv_keys)} CSV file(s)")
    records = _read_processed_csvs(csv_keys)
    print(f"[DataCollection] Loaded {len(records):,} records")

    if not records:
        raise ValueError("No valid records in processed CSVs (check spot_id / datetime columns)")

    # ---- 2. Load pre-fetched Surfline ratings from S3 ------------------
    ratings = _load_ratings_from_s3()
    print(f"[DataCollection] Loaded {len(ratings):,} rating entries from S3")

    spot_ids_in_ratings = len({k[0] for k in ratings})
    print(f"[DataCollection] Ratings cover {spot_ids_in_ratings} unique spots")

    # ---- 3. Merge records with ratings ---------------------------------
    labeled = []
    for rec in records:
        unix_ts = _dt_to_unix(rec["datetime"])
        if unix_ts is None:
            continue
        rating_val = ratings.get((rec["spot_id"], unix_ts))
        if rating_val is None:
            continue
        target = min(4, max(0, round(rating_val)))
        row = {"rating_value": target}
        for col in FEATURE_COLS:
            row[col] = rec.get(col, "")
        labeled.append(row)

    print(f"[DataCollection] Labeled {len(labeled):,} / {len(records):,} records")

    if not labeled:
        raise ValueError(
            "No records matched ratings. "
            "Check that ratings/surfline_ratings_latest.csv covers the same spot_ids "
            "and time window as the processed CSVs."
        )

    # ---- 4. Write labeled CSV to ML bucket -----------------------------
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")

    buf = io.StringIO()
    fieldnames = ["rating_value"] + FEATURE_COLS
    writer = csv.DictWriter(buf, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(labeled)
    csv_bytes = buf.getvalue().encode("utf-8")

    # Timestamped copy for audit trail
    s3.put_object(
        Bucket=S3_BUCKET_ML,
        Key=f"training/labeled_{timestamp}.csv",
        Body=csv_bytes,
        ContentType="text/csv",
    )

    # Fixed path — SageMaker Preprocessing step reads from training/latest/
    latest_key = "training/latest/labeled.csv"
    s3.put_object(
        Bucket=S3_BUCKET_ML,
        Key=latest_key,
        Body=csv_bytes,
        ContentType="text/csv",
    )

    print(f"[DataCollection] Saved {len(labeled):,} records → training/latest/labeled.csv")

    # SageMaker Pipeline Lambda step output format
    return {
        "OutputParameters": [
            {"Name": "TrainingS3Uri", "Value": f"s3://{S3_BUCKET_ML}/{latest_key}"}
        ]
    }
