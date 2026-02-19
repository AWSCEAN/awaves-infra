"""
Lambda: Preprocessing
Transform raw JSON forecast data from S3 into processed format.
Merges marine + weather data, flattens hourly arrays, adds spot_id.

Input event (from Step Functions):
  {
    "date": "2026-02-15",
    "s3_prefix": "s3://bucket/raw/2026-02-15/",
    "total_spots": 1045
  }

Output:
  Saves processed JSON to S3: s3://{bucket_processed}/processed/{date}/forecast.json
  Returns: { "status": "success", "date": "...", "records": N }
"""

import json
import os
from datetime import datetime, timezone

import boto3

S3_BUCKET_RAW = os.environ["S3_BUCKET_RAW"]
S3_BUCKET_PROCESSED = os.environ["S3_BUCKET_PROCESSED"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

s3 = boto3.client("s3")

MARINE_VARS = [
    "wave_height", "wave_direction", "wave_period",
    "swell_wave_height", "swell_wave_direction", "swell_wave_period",
    "sea_surface_temperature", "ocean_current_velocity", "sea_level_height_msl",
]
WEATHER_VARS = [
    "temperature_2m", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
]


def _list_batch_files(prefix, file_prefix):
    """List all batch files matching a prefix."""
    response = s3.list_objects_v2(
        Bucket=S3_BUCKET_RAW, Prefix=f"{prefix}/{file_prefix}"
    )
    return sorted(
        [obj["Key"] for obj in response.get("Contents", [])],
    )


def _load_json(key):
    """Load JSON from S3."""
    obj = s3.get_object(Bucket=S3_BUCKET_RAW, Key=key)
    return json.loads(obj["Body"].read().decode())


def _flatten_hourly(api_response, variables):
    """Flatten Open-Meteo hourly response into list of records per location."""
    records = []

    # Handle single location (dict) vs batch (list)
    if isinstance(api_response, list):
        locations = api_response
    elif "hourly" in api_response:
        locations = [api_response]
    else:
        return records

    for loc_data in locations:
        hourly = loc_data.get("hourly", {})
        times = hourly.get("time", [])
        lat = loc_data.get("latitude")
        lon = loc_data.get("longitude")

        for t_idx, timestamp in enumerate(times):
            record = {
                "lat": lat,
                "lon": lon,
                "datetime": timestamp,
            }
            for var in variables:
                values = hourly.get(var, [])
                record[var] = values[t_idx] if t_idx < len(values) else None
            records.append(record)

    return records


def handler(event, context):
    date_str = event.get("date", datetime.now(timezone.utc).strftime("%Y-%m-%d"))
    raw_prefix = f"raw/{date_str}"

    # List batch files
    marine_files = _list_batch_files(raw_prefix, "marine_")
    weather_files = _list_batch_files(raw_prefix, "weather_")

    if not marine_files:
        return {"status": "error", "message": f"No marine data found for {date_str}"}

    # Process all batches
    all_records = []

    for m_file, w_file in zip(marine_files, weather_files):
        marine_data = _load_json(m_file)
        weather_data = _load_json(w_file)

        marine_records = _flatten_hourly(marine_data, MARINE_VARS)
        weather_records = _flatten_hourly(weather_data, WEATHER_VARS)

        # Merge marine + weather by (lat, lon, datetime)
        weather_lookup = {}
        for wr in weather_records:
            key = (wr["lat"], wr["lon"], wr["datetime"])
            weather_lookup[key] = wr

        for mr in marine_records:
            key = (mr["lat"], mr["lon"], mr["datetime"])
            wr = weather_lookup.get(key, {})
            merged = {**mr}
            for var in WEATHER_VARS:
                merged[var] = wr.get(var)

            # Create location ID matching DynamoDB schema
            if mr["lat"] is not None and mr["lon"] is not None:
                merged["location_id"] = f"{mr['lat']}#{mr['lon']}"

            all_records.append(merged)

    # Save processed data to S3
    output_key = f"processed/{date_str}/forecast.json"
    s3.put_object(
        Bucket=S3_BUCKET_PROCESSED,
        Key=output_key,
        Body=json.dumps(all_records),
        ContentType="application/json",
    )

    return {
        "status": "success",
        "date": date_str,
        "records": len(all_records),
        "output": f"s3://{S3_BUCKET_PROCESSED}/{output_key}",
    }
