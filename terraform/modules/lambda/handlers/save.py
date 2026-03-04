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

DynamoDB item written (awaves-dev-surf-info):
  locationId (PK), surfTimestamp (SK), expiredAt (TTL),
  geo { lat, lng },
  location { displayName, city, state, country },
  conditions { waveHeight, wavePeriod, windSpeed, waterTemperature },
  derivedMetrics {
    BEGINNER     { surfScore, surfGrade },
    INTERMEDIATE { surfScore, surfGrade },
    ADVANCED     { surfScore, surfGrade },
  },
  metadata { modelVersion, dataSource, predictionType, createdAt }

ElastiCache key: awaves:surf:latest:{locationId}
  -> nearest upcoming forecast record per location, TTL 3h

Saved-spot change detection:
  After writing surf data, scans awaves-dev-saved-list for users who have
  saved spots at each updated location, flags changed items with
  flagChange=true + changeMessage JSON, and invalidates their saved cache.
"""

import csv
import io
import json
import os
from datetime import datetime, timezone, timedelta
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr

# ── Environment ───────────────────────────────────────────────────────────────
S3_BUCKET = os.environ["S3_BUCKET_DATALAKE"]
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]
SAVED_LIST_TABLE = os.environ.get("DYNAMODB_SAVED_LIST_TABLE", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
ELASTICACHE_ENDPOINT = os.environ.get("ELASTICACHE_ENDPOINT", "")
MODEL_VERSION = os.environ.get("MODEL_VERSION", "awaves-v1")
LOCATIONS_TABLE = os.environ.get("DYNAMODB_LOCATIONS_TABLE", f"awaves-{ENVIRONMENT}-locations")

# ── AWS clients ───────────────────────────────────────────────────────────────
s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DYNAMODB_TABLE)
_saved_table = None
_locations_table = None
_redis_client = None
_location_cache = {}


def _get_saved_table():
    global _saved_table
    if _saved_table is None and SAVED_LIST_TABLE:
        _saved_table = dynamodb.Table(SAVED_LIST_TABLE)
    return _saved_table


def _get_locations_table():
    global _locations_table
    if _locations_table is None and LOCATIONS_TABLE:
        _locations_table = dynamodb.Table(LOCATIONS_TABLE)
    return _locations_table


def _get_location_info(location_id):
    if location_id in _location_cache:
        return _location_cache[location_id]

    loc_tbl = _get_locations_table()
    location = {"displayName": "", "city": "", "state": "", "country": ""}

    if loc_tbl:
        try:
            resp = loc_tbl.get_item(Key={"locationId": location_id})
            loc = resp.get("Item", {})
            location = {
                "displayName": loc.get("displayName", ""),
                "city":        loc.get("city", ""),
                "state":       loc.get("state", ""),
                "country":     loc.get("country", ""),
            }
        except Exception as e:
            print(f"[save] Failed to fetch location {location_id}: {e}")

    _location_cache[location_id] = location
    return location


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


# ── Pure helpers ──────────────────────────────────────────────────────────────

def _surf_grade(score):
    """Convert surf score (0-100) to grade (0-4)."""
    if score is None:
        return 0
    try:
        s = float(score)
    except (TypeError, ValueError):
        return 0
    if s >= 80:
        return 4
    elif s >= 60:
        return 3
    elif s >= 40:
        return 2
    elif s >= 20:
        return 1
    return 0


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
    """TTL = surfTimestamp + 9 hours as Unix timestamp (DynamoDB TTL)."""
    try:
        dt = datetime.fromisoformat(surf_timestamp_str.replace("Z", "+00:00"))
        return int((dt + timedelta(hours=9)).timestamp())
    except Exception:
        return None


def _has_significant_change(old_val, new_val):
    """Return True if old and new values differ by more than a float epsilon."""
    try:
        return abs(float(new_val) - float(old_val)) > 0.001
    except (TypeError, ValueError):
        return str(old_val) != str(new_val)


# ── S3 helpers ────────────────────────────────────────────────────────────────

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


# ── Change detection ──────────────────────────────────────────────────────────

def _detect_and_flag_changes(latest_per_location, r):
    """
    For each updated location, scan awaves-dev-saved-list for matching saved
    items, compare surf metrics, flag changed items, and invalidate the
    user's saved-items cache.

    Returns the count of saved items flagged.
    """
    if not SAVED_LIST_TABLE:
        print("[change] DYNAMODB_SAVED_LIST_TABLE not set — skipping change detection")
        return 0

    tbl = _get_saved_table()
    if not tbl:
        return 0

    flagged = 0
    affected_users = set()

    for location_id, (_, cache_data) in latest_per_location.items():
        new_conditions = cache_data["conditions"]
        new_derived = cache_data["derivedMetrics"]

        # Paginated scan: find all saved items for this location
        saved_items = []
        scan_kwargs = {"FilterExpression": Attr("locationId").eq(location_id)}
        while True:
            resp = tbl.scan(**scan_kwargs)
            saved_items.extend(resp.get("Items", []))
            if "LastEvaluatedKey" not in resp:
                break
            scan_kwargs["ExclusiveStartKey"] = resp["LastEvaluatedKey"]

        if not saved_items:
            continue

        print(f"[change] {location_id}: {len(saved_items)} saved item(s) to check")

        for item in saved_items:
            user_id = item.get("userId")
            sort_key = item.get("sortKey")
            if not user_id or not sort_key:
                continue

            # Map the user's SurferLevel directly to derivedMetrics key
            # (BEGINNER | INTERMEDIATE | ADVANCED — 1:1 match)
            surfer_level = item.get("surferLevel", "BEGINNER")
            level_data = new_derived.get(surfer_level) or new_derived.get("BEGINNER", {})
            new_score = level_data.get("surfScore", 0.0)
            new_grade = level_data.get("surfGrade", "F")

            # Compare the 5 tracked metrics
            comparisons = [
                ("surfScore",        item.get("surfScore"),        new_score),
                ("waveHeight",       item.get("waveHeight"),       new_conditions["waveHeight"]),
                ("wavePeriod",       item.get("wavePeriod"),       new_conditions["wavePeriod"]),
                ("windSpeed",        item.get("windSpeed"),        new_conditions["windSpeed"]),
                ("waterTemperature", item.get("waterTemperature"), new_conditions["waterTemperature"]),
            ]
            changes = []
            for field, old_val, new_val in comparisons:
                if old_val is not None and _has_significant_change(old_val, new_val):
                    changes.append({
                        "field": field,
                        "old":   round(float(old_val), 2),
                        "new":   round(float(new_val), 2),
                    })

            if not changes:
                continue

            # Flag the saved item with the latest values
            change_message = json.dumps({"changes": changes})
            try:
                tbl.update_item(
                    Key={"userId": user_id, "sortKey": sort_key},
                    UpdateExpression=(
                        "SET flagChange = :fc, changeMessage = :cm, "
                        "surfScore = :ss, surfGrade = :sg, "
                        "waveHeight = :wh, wavePeriod = :wp, "
                        "windSpeed = :ws, waterTemperature = :wt"
                    ),
                    ExpressionAttributeValues={
                        ":fc": True,
                        ":cm": change_message,
                        ":ss": _to_decimal(new_score),
                        ":sg": new_grade,
                        ":wh": _to_decimal(new_conditions["waveHeight"]),
                        ":wp": _to_decimal(new_conditions["wavePeriod"]),
                        ":ws": _to_decimal(new_conditions["windSpeed"]),
                        ":wt": _to_decimal(new_conditions["waterTemperature"]),
                    },
                )
                flagged += 1
                affected_users.add(user_id)
                print(f"[change] Flagged: user={user_id} key={sort_key} changes={[c['field'] for c in changes]}")
            except Exception as e:
                print(f"[change] Failed to flag {user_id}/{sort_key}: {e}")

    # Invalidate saved-items cache for all affected users
    if r and affected_users:
        try:
            pipe = r.pipeline()
            for uid in affected_users:
                pipe.delete(f"awaves:saved:{uid}")
            pipe.execute()
            print(f"[change] Invalidated awaves:saved cache for {len(affected_users)} user(s)")
        except Exception as e:
            print(f"[change] Cache invalidation error: {e}")

    return flagged


# ── Handler ───────────────────────────────────────────────────────────────────

def handler(event, context):
    print(f"[save] START table={DYNAMODB_TABLE} saved_table={SAVED_LIST_TABLE!r} endpoint={ELASTICACHE_ENDPOINT!r}")
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

    # Track nearest upcoming record per location for ElastiCache
    # { locationId -> (datetime, cache_dict) }
    latest_per_location = {}

    with table.batch_writer() as batch:
        for key in out_files:
            try:
                rows = _read_csv_from_s3(key)
            except Exception as e:
                print(f"[save] Failed to read {key}: {e}")
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
                location = _get_location_info(location_id)

                item = {
                    "locationId": location_id,
                    "surfTimestamp": dt_str,
                    "expiredAt": _expired_at(dt_str),
                    "geo": {
                        "lat": _to_decimal(lat),
                        "lng": _to_decimal(lng),
                    },
                    "location": location,
                    "conditions": {
                        "waveHeight":       _to_decimal(row.get("wave_height")),
                        "wavePeriod":       _to_decimal(row.get("wave_period")),
                        "windSpeed":        _to_decimal(row.get("wind_speed_10m")),
                        "waterTemperature": _to_decimal(row.get("sea_surface_temperature")),
                    },
                    "derivedMetrics": {
                        "BEGINNER": {
                            "surfScore": _to_decimal(y_beg),
                            "surfGrade": _surf_grade(y_beg),
                        },
                        "INTERMEDIATE": {
                            "surfScore": _to_decimal(y_int),
                            "surfGrade": _surf_grade(y_int),
                        },
                        "ADVANCED": {
                            "surfScore": _to_decimal(y_adv),
                            "surfGrade": _surf_grade(y_adv),
                        },
                    },
                    "metadata": {
                        "modelVersion":  MODEL_VERSION,
                        "dataSource":    "open-meteo",
                        "predictionType": "FORECAST",
                        "createdAt":     created_at,
                    },
                }

                try:
                    batch.put_item(Item=item)
                    written += 1
                except Exception as e:
                    print(f"[save] DynamoDB put_item failed for {location_id}: {e}")
                    errors += 1
                    continue

                # Track nearest upcoming record per location for ElastiCache
                try:
                    row_dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
                    if row_dt >= now_ts:
                        prev = latest_per_location.get(location_id)
                        if prev is None or row_dt < prev[0]:
                            wh  = float(row.get("wave_height") or 0)
                            wp  = float(row.get("wave_period") or 0)
                            ws  = float(row.get("wind_speed_10m") or 0)
                            wt  = float(row.get("sea_surface_temperature") or 0)
                            beg_score = round(float(y_beg), 1) if y_beg else 0.0
                            int_score = round(float(y_int), 1) if y_int else 0.0
                            adv_score = round(float(y_adv), 1) if y_adv else 0.0

                            latest_per_location[location_id] = (row_dt, {
                                "locationId":    location_id,
                                "surfTimestamp": dt_str,
                                "geo": {
                                    "lat": lat,
                                    "lng": lng,
                                },
                                "location": location,
                                "conditions": {
                                    "waveHeight":       wh,
                                    "wavePeriod":       wp,
                                    "windSpeed":        ws,
                                    "waterTemperature": wt,
                                },
                                "derivedMetrics": {
                                    "BEGINNER": {
                                        "surfScore": beg_score,
                                        "surfGrade": _surf_grade(y_beg),
                                    },
                                    "INTERMEDIATE": {
                                        "surfScore": int_score,
                                        "surfGrade": _surf_grade(y_int),
                                    },
                                    "ADVANCED": {
                                        "surfScore": adv_score,
                                        "surfGrade": _surf_grade(y_adv),
                                    },
                                },
                                "metadata": {
                                    "modelVersion":   MODEL_VERSION,
                                    "dataSource":     "open-meteo",
                                    "predictionType": "FORECAST",
                                    "createdAt":      created_at,
                                    "cacheSource":    "SURF_LATEST",
                                },
                            })
                except Exception:
                    pass

    print(f"[save] DynamoDB batch complete: written={written} errors={errors}")

    # Write latest per location to ElastiCache (TTL = 3 hours)
    cache_written = 0
    r = None
    try:
        r = _get_valkey()
        if r and latest_per_location:
            pipe = r.pipeline()
            for location_id, (_, cache_data) in latest_per_location.items():
                pipe.setex(
                    f"awaves:surf:latest:{location_id}",
                    10800,  # 3 hours
                    json.dumps(cache_data),
                )
                cache_written += 1
            pipe.execute()
            print(f"[save] ElastiCache: wrote {cache_written} location(s) with 3h TTL")
    except Exception as e:
        print(f"[save] ElastiCache error: {e}")
        cache_written = 0

    # Detect and flag changes in saved spots
    saved_flagged = 0
    try:
        saved_flagged = _detect_and_flag_changes(latest_per_location, r)
        print(f"[save] Change detection complete: {saved_flagged} saved item(s) flagged")
    except Exception as e:
        print(f"[save] Change detection error: {e}")

    return {
        "status": "success" if errors == 0 else "partial",
        "inference_prefix": inference_prefix,
        "files_processed": len(out_files),
        "written": written,
        "errors": errors,
        "cache_written": cache_written,
        "saved_flagged": saved_flagged,
    }
