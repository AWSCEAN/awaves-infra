"""
Lambda: Save
Read BatchTransform inference output (.out CSV) from S3 and persist to
DynamoDB (awaves-{env}-surf-info) and ElastiCache.

Pipeline position: BatchTransform -> DriftDetection -> SaveToDatabase

Input event:
  { "inference_prefix": "inference/2026/02/22/14/" }

Output CSV columns (from inference.py):
  location_id, spot_id, datetime,
  y_pred_adv, y_pred_int, y_pred_beg,   <- 0-100 scale
  wave_height, wave_period, wind_speed_10m, sea_surface_temperature

DynamoDB item written:
  locationId (PK), surfTimestamp (SK), expiredAt (TTL),
  geo { lat, lng },
  conditions { waveHeight, wavePeriod, windSpeed, waterTemperature },
  derivedMetrics { surfScoreAdv/Int/Beg, surfGradeAdv/Int/Beg },
  metadata { modelVersion, dataSource, predictionType, createdAt }

ElastiCache key: awaves:surf:latest:{locationId}
  -> nearest upcoming forecast record per location, TTL 3h
"""

import csv
import io
import json
import os
from datetime import datetime, timezone, timedelta
from decimal import Decimal

import boto3

S3_BUCKET = os.environ["S3_BUCKET_DATALAKE"]
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
ELASTICACHE_ENDPOINT = os.environ.get("ELASTICACHE_ENDPOINT", "")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "awaves-v1")

CACHE_TTL_SECONDS = 3 * 3600  # 3 hours

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DYNAMODB_TABLE)

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
            socket_timeout=2,
        )
    return _redis_client


def _surf_grade(score):
    if score is None:
        return "F"
    try:
        s = float(score)
    except (TypeError, ValueError):
        return "F"
    if s >= 80:
        return "A"
    elif s >= 60:
        return "B"
    elif s >= 40:
        return "C"
    elif s >= 20:
        return "D"
    return "F"


def _to_decimal(value):
    if value is None:
        return None
    try:
        return Decimal(str(round(float(value), 4)))
    except (TypeError, ValueError):
        return None


def _parse_geo(location_id):
    try:
        lat_str, lng_str = location_id.split("#")
        return float(lat_str), float(lng_str)
    except Exception:
        return None, None


def _expired_at(surf_timestamp_str):
    """TTL = surfTimestamp + 7 days as Unix timestamp (DynamoDB TTL)."""
    try:
        dt = datetime.fromisoformat(surf_timestamp_str.replace("Z", "+00:00"))
        return int((dt + timedelta(days=7)).timestamp())
    except Exception:
        return None


def _list_out_files(prefix):
    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=S3_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Key"].endswith(".out"):
                keys.append(obj["Key"])
    return sorted(keys)


def _read_csv_from_s3(key):
    obj = s3.get_object(Bucket=S3_BUCKET, Key=key)
    content = obj["Body"].read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(content)))


def handler(event, context):
    print(f"[save] START table={DYNAMODB_TABLE} endpoint={ELASTICACHE_ENDPOINT!r}")
    inference_prefix = event.get("inference_prefix", "inference/")
    created_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    now_ts = datetime.now(timezone.utc)

    out_files = _list_out_files(inference_prefix)
    print(f"[save] found {len(out_files)} .out files under {inference_prefix}")
    if not out_files:
        return {
            "status": "error",
            "message": f"No .out files found at s3://{S3_BUCKET}/{inference_prefix}",
        }

    written = 0
    errors = 0

    # Track nearest future record per location for ElastiCache
    # { locationId -> (datetime, cache_dict) }
    latest_per_location = {}

    with table.batch_writer() as batch:
        for key in out_files:
            try:
                rows = _read_csv_from_s3(key)
            except Exception:
                errors += 1
                continue

            for row in rows:
                location_id = row.get("location_id")
                dt_str = row.get("datetime")

                if not location_id or not dt_str:
                    errors += 1
                    continue

                y_adv = row.get("y_pred_adv")
                if y_adv is None:
                    errors += 1
                    continue

                y_int = row.get("y_pred_int")
                y_beg = row.get("y_pred_beg")
                lat, lng = _parse_geo(location_id)

                item = {
                    "locationId": location_id,
                    "surfTimestamp": dt_str,
                    "expiredAt": _expired_at(dt_str),
                    "geo": {
                        "lat": _to_decimal(lat),
                        "lng": _to_decimal(lng),
                    },
                    "conditions": {
                        "waveHeight": _to_decimal(row.get("wave_height")),
                        "wavePeriod": _to_decimal(row.get("wave_period")),
                        "windSpeed": _to_decimal(row.get("wind_speed_10m")),
                        "waterTemperature": _to_decimal(row.get("sea_surface_temperature")),
                    },
                    "derivedMetrics": {
                        "surfScoreAdv": _to_decimal(y_adv),
                        "surfScoreInt": _to_decimal(y_int),
                        "surfScoreBeg": _to_decimal(y_beg),
                        "surfGradeAdv": _surf_grade(y_adv),
                        "surfGradeInt": _surf_grade(y_int),
                        "surfGradeBeg": _surf_grade(y_beg),
                    },
                    "metadata": {
                        "modelVersion": MODEL_VERSION,
                        "dataSource": "open-meteo",
                        "predictionType": "FORECAST",
                        "createdAt": created_at,
                    },
                }

                try:
                    batch.put_item(Item=item)
                    written += 1
                except Exception:
                    errors += 1
                    continue

                # Track nearest upcoming record for ElastiCache
                try:
                    row_dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
                    if row_dt >= now_ts:
                        prev = latest_per_location.get(location_id)
                        if prev is None or row_dt < prev[0]:
                            latest_per_location[location_id] = (row_dt, {
                                "locationId": location_id,
                                "lat": lat,
                                "lng": lng,
                                "surfScoreAdv": round(float(y_adv), 1) if y_adv else 0.0,
                                "surfScoreInt": round(float(y_int), 1) if y_int else 0.0,
                                "surfScoreBeg": round(float(y_beg), 1) if y_beg else 0.0,
                                "surfGradeAdv": _surf_grade(y_adv),
                                "surfGradeInt": _surf_grade(y_int),
                                "surfGradeBeg": _surf_grade(y_beg),
                                "waveHeight": float(row.get("wave_height") or 0),
                                "wavePeriod": float(row.get("wave_period") or 0),
                                "lastUpdated": created_at,
                            })
                except Exception:
                    pass

    print(f"[save] DynamoDB batch complete: written={written} errors={errors}")

    # Write latest per location to ElastiCache
    cache_written = 0
    try:
        r = _get_valkey()
        if r and latest_per_location:
            pipe = r.pipeline()
            for location_id, (_, cache_data) in latest_per_location.items():
                pipe.set(
                    f"awaves:surf:latest:{location_id}",
                    json.dumps(cache_data),
                    ex=CACHE_TTL_SECONDS,
                )
                cache_written += 1
            pipe.execute()
    except Exception as e:
        print(f"[save] ElastiCache error: {e}")
        cache_written = 0

    return {
        "status": "success" if errors == 0 else "partial",
        "inference_prefix": inference_prefix,
        "files_processed": len(out_files),
        "written": written,
        "errors": errors,
        "cache_written": cache_written,
    }
