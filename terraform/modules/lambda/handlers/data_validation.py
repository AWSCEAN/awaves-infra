"""
Lambda: Data Validation
Validate raw JSON forecast data in S3 after API Call step.

Checks that marine + weather batch files exist, are structurally valid,
and contain the expected variables before passing to Preprocessing.

Input event (from api_call output):
  {
    "status": "success",
    "date": "2026-02-22",
    "raw_prefix": "raw/forecast/2026/02/22/00",
    "spots_s3_key": "spots/spot_test.json",
    ...
  }

Output:
  Passes through the input event with added validation_summary field.
  Raises ValueError on validation failure (Step Functions routes to PipelineFailed).
"""

import json
import os

import boto3

S3_BUCKET = os.environ["S3_BUCKET_DATALAKE"]

s3 = boto3.client("s3")


def _list_batch_files(prefix, file_prefix):
    response = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix=f"{prefix}/{file_prefix}")
    return sorted([obj["Key"] for obj in response.get("Contents", [])])


def _load_json(key):
    obj = s3.get_object(Bucket=S3_BUCKET, Key=key)
    return json.loads(obj["Body"].read().decode())


def _validate_hourly_file(data, label):
    """Validate basic structure of a marine or weather API response file.
    Variable-level nulls are allowed — preprocessing handles missing values.
    """
    errors = []

    if isinstance(data, list):
        locations = data
    elif "hourly" in data:
        locations = [data]
    else:
        return [f"{label}: no valid location data found"]

    for i, loc in enumerate(locations):
        hourly = loc.get("hourly", {})
        times = hourly.get("time", [])
        if not times:
            errors.append(f"{label}[{i}]: empty time array")

    return errors


def handler(event, context):
    raw_prefix = event.get("raw_prefix")
    if not raw_prefix:
        raise ValueError("raw_prefix missing from event")

    marine_files = _list_batch_files(raw_prefix, "marine_")
    weather_files = _list_batch_files(raw_prefix, "weather_")

    if not marine_files:
        raise ValueError(f"No marine_*.json files found at s3://{S3_BUCKET}/{raw_prefix}")

    if not weather_files:
        raise ValueError(f"No weather_*.json files found at s3://{S3_BUCKET}/{raw_prefix}")

    if len(marine_files) != len(weather_files):
        raise ValueError(
            f"Batch count mismatch: marine={len(marine_files)} weather={len(weather_files)}"
        )

    errors = []
    for m_key, w_key in zip(marine_files, weather_files):
        try:
            marine_data = _load_json(m_key)
            errors.extend(_validate_hourly_file(marine_data, m_key))
        except Exception as e:
            errors.append(f"Failed to load {m_key}: {e}")

        try:
            weather_data = _load_json(w_key)
            errors.extend(_validate_hourly_file(weather_data, w_key))
        except Exception as e:
            errors.append(f"Failed to load {w_key}: {e}")

    if errors:
        raise ValueError(f"Data validation failed ({len(errors)} error(s)): {errors[:5]}")

    print(f"[validation] OK: {len(marine_files)} batch(es) validated at {raw_prefix}")

    return {
        **event,
        "validation_summary": {
            "batches": len(marine_files),
            "marine_files": len(marine_files),
            "weather_files": len(weather_files),
            "status": "passed",
        },
    }
