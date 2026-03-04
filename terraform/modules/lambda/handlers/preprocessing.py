"""
Lambda: Preprocessing
Transform raw JSON forecast data from S3 into processed CSV format.
Merges marine + weather data, flattens hourly arrays, adds spot metadata,
and engineers features for model inference.

Input event (from Step Functions / api_call output):
  {
    "date": "2026-02-22",
    "raw_prefix": "raw/forecast/2026/02/22/00",
    "spots_s3_key": "spots/spot_test.json"   (optional)
  }

Output:
  Saves processed CSV to S3: s3://{bucket}/processed/YYYY/MM/DD/HH/forecast_NNNN.csv
  Returns: { "status": "success", "date": "...", "raw_prefix": "...", "processed_prefix": "...", "records": N }
"""

import csv
import io
import json
import math
import os
from datetime import datetime, timezone

import boto3

S3_BUCKET = os.environ["S3_BUCKET_DATALAKE"]
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

# Column order must match model training (train_rating_hourly.ipynb feature_cols)
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

# Must match api_call.BATCH_SIZE so we can slice the spots list by batch index
BATCH_SIZE = 250

# Metadata cols written alongside features for DynamoDB save step
META_COLS = ["location_id", "spot_id", "datetime"]

CSV_COLS = META_COLS + FEATURE_COLS


def _list_batch_files(prefix, file_prefix):
    """List all batch files matching a prefix."""
    response = s3.list_objects_v2(
        Bucket=S3_BUCKET, Prefix=f"{prefix}/{file_prefix}"
    )
    return sorted(
        [obj["Key"] for obj in response.get("Contents", [])],
    )


def _load_json(key):
    """Load JSON from S3."""
    obj = s3.get_object(Bucket=S3_BUCKET, Key=key)
    return json.loads(obj["Body"].read().decode())


def _flatten_hourly(api_response, variables, original_spots=None):
    """Flatten Open-Meteo hourly response into list of records per location.

    original_spots: list of spot dicts (from api_call's spots_{batch}.json).
      When provided, uses the i-th spot's lat/lon instead of Open-Meteo's
      grid-snapped coordinates so that location_id matches awaves-dev-locations.
    """
    records = []

    if isinstance(api_response, list):
        locations = api_response
    elif "hourly" in api_response:
        locations = [api_response]
    else:
        return records

    for idx, loc_data in enumerate(locations):
        hourly = loc_data.get("hourly", {})
        times = hourly.get("time", [])

        # Prefer original spot coordinates to avoid Open-Meteo grid snapping
        if original_spots and idx < len(original_spots):
            lat = original_spots[idx]["lat"]
            lon = original_spots[idx]["lon"]
        else:
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


def _safe(v):
    return v if v is not None else None


def _rel_sin_cos(direction, coastline_angle):
    """Compute sin/cos of direction relative to coastline_angle."""
    if direction is None or coastline_angle is None:
        return None, None
    rel = (direction - coastline_angle + 180) % 360
    return math.sin(math.radians(rel)), math.cos(math.radians(rel))


def _engineer_features(rec):
    """Add derived features to a merged record in-place."""
    ca = rec.get("coastline_angle")
    wh = rec.get("wave_height")
    wp = rec.get("wave_period")
    wd = rec.get("wave_direction")
    swh = rec.get("swell_wave_height")
    swp = rec.get("swell_wave_period")
    swd = rec.get("swell_wave_direction")
    ws = rec.get("wind_speed_10m")
    wg = rec.get("wind_gusts_10m")
    wdir = rec.get("wind_direction_10m")
    lat = rec.get("lat")

    # Relative direction features
    wave_sin, wave_cos = _rel_sin_cos(wd, ca)
    swell_sin, swell_cos = _rel_sin_cos(swd, ca)
    wind_sin, wind_cos = _rel_sin_cos(wdir, ca)

    rec["wave_direction_rel_sin"] = wave_sin
    rec["wave_direction_rel_cos"] = wave_cos
    rec["swell_wave_direction_rel_sin"] = swell_sin
    rec["swell_wave_direction_rel_cos"] = swell_cos
    rec["wind_direction_10m_rel_sin"] = wind_sin
    rec["wind_direction_10m_rel_cos"] = wind_cos

    # Interaction terms
    rec["wave_power"] = (wh ** 2 * wp) if wh is not None and wp is not None else None
    rec["swell_power"] = (swh ** 2 * swp) if swh is not None and swp is not None else None
    rec["wind_wave_ratio"] = (ws / (wh + 0.01)) if ws is not None and wh is not None else None
    rec["gust_factor"] = (wg / (ws + 0.01)) if wg is not None and ws is not None else None
    rec["wave_steepness"] = (wh / (wp + 0.01)) if wh is not None and wp is not None else None

    # Vector decomposition
    wave_power = rec["wave_power"]
    swell_power = rec["swell_power"]
    rec["wind_onshore"] = (ws * wind_cos) if ws is not None and wind_cos is not None else None
    rec["wind_cross"] = (ws * wind_sin) if ws is not None and wind_sin is not None else None
    rec["gust_onshore"] = (wg * wind_cos) if wg is not None and wind_cos is not None else None
    rec["wave_shore_power"] = (wave_power * wave_cos) if wave_power is not None and wave_cos is not None else None
    rec["swell_shore_power"] = (swell_power * swell_cos) if swell_power is not None and swell_cos is not None else None
    rec["swell_cross_power"] = (swell_power * swell_sin) if swell_power is not None and swell_sin is not None else None

    # Location
    rec["abs_lat"] = abs(lat) if lat is not None else None


def handler(event, context):
    # Load spot metadata (lat/lon -> spot_id, coastline_angle)
    spots_key = event.get("spots_s3_key", "spots/spot_test.json")
    obj = s3.get_object(Bucket=S3_BUCKET, Key=spots_key)
    spots = json.load(obj["Body"])["spots"]
    spot_lookup = {(s["lat"], s["lon"]): s for s in spots}

    # Resolve raw prefix from api_call output or fallback
    raw_prefix = event.get("raw_prefix")
    date_str = event.get("date", datetime.now(timezone.utc).strftime("%Y-%m-%d"))
    if not raw_prefix:
        raw_prefix = f"raw/forecast/{date_str.replace('-', '/')}"

    # List batch files
    marine_files = _list_batch_files(raw_prefix, "marine_")
    weather_files = _list_batch_files(raw_prefix, "weather_")

    if not marine_files:
        return {"status": "error", "message": f"No marine data found at {raw_prefix}"}

    # Process each batch and write immediately to avoid OOM
    hour_path = raw_prefix.replace("raw/forecast/", "")
    total_records = 0

    for batch_idx, (m_file, w_file) in enumerate(zip(marine_files, weather_files)):
        marine_data = _load_json(m_file)
        weather_data = _load_json(w_file)

        # Recover original spot coordinates.
        # Primary: load spots_{batch}.json saved by api_call alongside the API response.
        # Fallback: reconstruct from the global spots list by filename index.
        spots_file = m_file.replace("/marine_", "/spots_")
        try:
            batch_spots = _load_json(spots_file)
        except Exception:
            try:
                file_num = int(m_file.rsplit("marine_", 1)[1].replace(".json", ""))
                batch_spots = spots[file_num * BATCH_SIZE : (file_num + 1) * BATCH_SIZE]
                print(f"WARNING: spots file not found for {m_file}, using index-based fallback (file_num={file_num})")
            except Exception:
                batch_spots = []
                print(f"ERROR: Could not recover original spots for {m_file}, API grid-snapped coords will be used")

        marine_records = _flatten_hourly(marine_data, MARINE_VARS, original_spots=batch_spots)
        weather_records = _flatten_hourly(weather_data, WEATHER_VARS, original_spots=batch_spots)

        # Merge marine + weather by (lat, lon, datetime)
        weather_lookup = {}
        for wr in weather_records:
            key = (wr["lat"], wr["lon"], wr["datetime"])
            weather_lookup[key] = wr

        batch_records = []
        for mr in marine_records:
            key = (mr["lat"], mr["lon"], mr["datetime"])
            wr = weather_lookup.get(key, {})
            merged = {**mr}
            for var in WEATHER_VARS:
                merged[var] = wr.get(var)

            spot_meta = spot_lookup.get((mr["lat"], mr["lon"]), {})
            merged["spot_id"] = spot_meta.get("spot_id")
            merged["coastline_angle"] = spot_meta.get("coastline_angle")

            if mr["lat"] is not None and mr["lon"] is not None:
                merged["location_id"] = f"{mr['lat']}#{mr['lon']}"

            _engineer_features(merged)
            batch_records.append(merged)

        # Write batch as CSV: processed/YYYY/MM/DD/HH/forecast_0000.csv
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=CSV_COLS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(batch_records)

        output_key = f"processed/{hour_path}/forecast_{batch_idx:04d}.csv"
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=output_key,
            Body=buf.getvalue().encode("utf-8"),
            ContentType="text/csv",
        )
        total_records += len(batch_records)

    return {
        "status": "success",
        "date": date_str,
        "raw_prefix": raw_prefix,
        "processed_prefix": f"processed/{hour_path}/",
        "inference_prefix": f"inference/{hour_path}/",
        "records": total_records,
    }
