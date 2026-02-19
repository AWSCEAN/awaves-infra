"""
Lambda: Save
Persist processed forecast data to DynamoDB.

Input event (from Step Functions):
  {
    "date": "2026-02-15",
    "output": "s3://bucket/processed/2026-02-15/forecast.json",
    "records": 250800
  }

Output:
  Writes records to DynamoDB surf-data table.
  Returns: { "status": "success", "written": N, "errors": N }
"""

import json
import os
from decimal import Decimal

import boto3

S3_BUCKET_PROCESSED = os.environ.get("S3_BUCKET_PROCESSED", "")
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DYNAMODB_TABLE)

# DynamoDB schema columns
NUMERIC_FIELDS = [
    "wave_height", "wave_direction", "wave_period",
    "swell_wave_height", "swell_wave_direction", "swell_wave_period",
    "sea_surface_temperature", "ocean_current_velocity", "sea_level_height_msl",
    "temperature_2m", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
]


def _to_decimal(value):
    """Convert float to Decimal for DynamoDB."""
    if value is None:
        return None
    return Decimal(str(value))


def handler(event, context):
    date_str = event.get("date", "")
    output_path = event.get("output", "")

    # Parse S3 path
    if output_path.startswith("s3://"):
        parts = output_path.replace("s3://", "").split("/", 1)
        bucket = parts[0]
        key = parts[1]
    else:
        bucket = S3_BUCKET_PROCESSED
        key = f"processed/{date_str}/forecast.json"

    # Load processed data
    obj = s3.get_object(Bucket=bucket, Key=key)
    records = json.loads(obj["Body"].read().decode())

    written = 0
    errors = 0

    # Batch write to DynamoDB (25 items per batch)
    with table.batch_writer() as batch:
        for record in records:
            location_id = record.get("location_id")
            dt = record.get("datetime")

            if not location_id or not dt:
                errors += 1
                continue

            item = {
                "LocationId": location_id,
                "SurfTimestamp": dt,
            }

            for field in NUMERIC_FIELDS:
                val = record.get(field)
                if val is not None:
                    item[field] = _to_decimal(val)

            try:
                batch.put_item(Item=item)
                written += 1
            except Exception:
                errors += 1

    return {
        "status": "success" if errors == 0 else "partial",
        "date": date_str,
        "written": written,
        "errors": errors,
        "total": len(records),
    }
