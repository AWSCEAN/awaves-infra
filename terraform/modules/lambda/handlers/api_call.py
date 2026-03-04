"""
Lambda: API Call
Fetch ocean/weather forecast data from Open-Meteo Marine + Weather APIs.
Triggered by Step Functions as part of the data collection pipeline.

Input event:
  {
    "spots_s3_key": "spots/spot.parquet"  (optional, default provided)
  }

Output:
  Saves raw JSON to S3: s3://{bucket}/raw/forecast/YYYY/MM/DD/HH/marine_{batch}.json, weather_{batch}.json
  Returns: { "status": "success", "date": "...", "raw_prefix": "...", "batches": N, "spots": N }
"""

import json
import os
import time
from datetime import datetime, timezone
from urllib.request import urlopen, Request
from urllib.error import HTTPError
from urllib.parse import urlencode
import urllib3

import boto3

S3_BUCKET = os.environ["S3_BUCKET_DATALAKE"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

MARINE_API_URL = "https://marine-api.open-meteo.com/v1/marine"
WEATHER_API_URL = "https://api.open-meteo.com/v1/forecast"

MARINE_HOURLY_VARS = ",".join([
    "wave_height", "wave_direction", "wave_period",
    "swell_wave_height", "swell_wave_direction", "swell_wave_period",
    "sea_surface_temperature", "ocean_current_velocity", "sea_level_height_msl",
])

WEATHER_HOURLY_VARS = ",".join([
    "temperature_2m", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
])

BATCH_SIZE = 250
BATCH_DELAY_SEC = 5

s3 = boto3.client("s3")


def _fetch_json(url, retries=3):
    """Fetch JSON from URL with retry on 429."""
    for attempt in range(retries):
        try:
            req = Request(url, headers={"User-Agent": "awaves-lambda"})
            with urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode())
        except HTTPError as e:
            if e.code == 429:
                retry_after = int(e.headers.get("Retry-After", 30))
                time.sleep(retry_after)
            elif attempt == retries - 1:
                raise
            else:
                time.sleep(5)
    return None


def _fetch_marine_batch(lats, lons):
    """Fetch marine forecast for a batch of coordinates."""
    params = urlencode({
        "latitude": ",".join(str(x) for x in lats),
        "longitude": ",".join(str(x) for x in lons),
        "hourly": MARINE_HOURLY_VARS,
        "forecast_days": 10,
    })
    return _fetch_json(f"{MARINE_API_URL}?{params}")


def _fetch_weather_batch(lats, lons):
    """Fetch weather forecast for a batch of coordinates."""
    params = urlencode({
        "latitude": ",".join(str(x) for x in lats),
        "longitude": ",".join(str(x) for x in lons),
        "hourly": WEATHER_HOURLY_VARS,
        "forecast_days": 10,
        "wind_speed_unit": "ms",
    })
    return _fetch_json(f"{WEATHER_API_URL}?{params}")


def handler(event, context):
    http = urllib3.PoolManager()
    ip = "unknown"
    try:
        response = http.request('GET', 'https://api.ipify.org?format=json', timeout=5.0)
        ip = json.loads(response.data.decode('utf-8')).get("ip")
    except Exception as e:
        print(f"Could not get public IP: {e}")
    print(f"My public IP: {ip}")

    now = datetime.now(timezone.utc)
    date_str = now.strftime("%Y-%m-%d")
    prefix = f"raw/forecast/{now.strftime('%Y/%m/%d/%H')}"

    # Load spot coordinates from S3
    spots_key = event.get("spots_s3_key", "spots/spot_test.json")
    try:
        obj = s3.get_object(Bucket=S3_BUCKET, Key=spots_key)
        spots = json.load(obj["Body"])["spots"]
    except Exception as e:
        return {"status": "error", "message": f"Failed to load spots: {str(e)}"}

    lats = [s["lat"] for s in spots]
    lons = [s["lon"] for s in spots]
    total_spots = len(lats)

    batches_completed = 0
    errors = []

    for i in range(0, total_spots, BATCH_SIZE):
        batch_lats = lats[i : i + BATCH_SIZE]
        batch_lons = lons[i : i + BATCH_SIZE]
        batch_idx = i // BATCH_SIZE

        try:
            # Save original spot coordinates for this batch so preprocessing
            # can recover them without depending on filename-based index mapping.
            batch_spot_meta = [{"lat": batch_lats[j], "lon": batch_lons[j]} for j in range(len(batch_lats))]
            s3.put_object(
                Bucket=S3_BUCKET,
                Key=f"{prefix}/spots_{batch_idx:04d}.json",
                Body=json.dumps(batch_spot_meta),
                ContentType="application/json",
            )

            # Fetch marine data
            marine_data = _fetch_marine_batch(batch_lats, batch_lons)
            s3.put_object(
                Bucket=S3_BUCKET,
                Key=f"{prefix}/marine_{batch_idx:04d}.json",
                Body=json.dumps(marine_data),
                ContentType="application/json",
            )

            # Fetch weather data
            weather_data = _fetch_weather_batch(batch_lats, batch_lons)
            s3.put_object(
                Bucket=S3_BUCKET,
                Key=f"{prefix}/weather_{batch_idx:04d}.json",
                Body=json.dumps(weather_data),
                ContentType="application/json",
            )

            batches_completed += 1
        except Exception as e:
            errors.append({"batch": batch_idx, "error": str(e)})

        if i + BATCH_SIZE < total_spots:
            time.sleep(BATCH_DELAY_SEC)

    return {
        "status": "success" if not errors else "partial",
        "date": date_str,
        "spots_s3_key": spots_key,
        "raw_prefix": prefix,
        "total_spots": total_spots,
        "batches_completed": batches_completed,
        "errors": errors[:5],
    }
