"""
Lambda: Bedrock Summary

DynamoDB에서 서핑 조건을 읽고 Bedrock(Claude)으로 한/영 조언을 생성한다.
동일 요청에 대해 DynamoDB 아이템에 결과를 캐싱한다.

DynamoDB schema (save.py 기준):
  PK: locationId  (camelCase)
  SK: surfTimestamp  (camelCase)
  conditions: { waveHeight, wavePeriod, windSpeed, waterTemperature }
  derivedMetrics: {
    BEGINNER:     { surfScore, surfGrade },
    INTERMEDIATE: { surfScore, surfGrade },
    ADVANCED:     { surfScore, surfGrade },
  }
  geo: { lat, lng }

Input event:
  {
    "location_id":    "35.1795#129.2185",
    "surf_timestamp": "2026-01-28T06:00:00Z",
    "surfing_level":     "LOW"  # LOW | MEDIUM | HIGH (Aurora users.surfing_level)
  }

Output:
  { "advice": { "ko": "...", "en": "..." }, "cache": "hit" | "miss" }

Cache strategy:
  DynamoDB UpdateItem으로 surf-info 아이템에 ai_summary_{LEVEL} 속성 추가.
  저장 형식: JSON 문자열 {"ko": "...", "en": "..."}
  3시간 배치 주기로 신규 아이템이 생성되므로 별도 TTL 불필요.
"""

import json
import math
import os

import boto3

BEDROCK_MODEL_ID        = os.environ.get("BEDROCK_MODEL_ID", "us.anthropic.claude-3-7-sonnet-20250219-v1:0")
DYNAMODB_TABLE          = os.environ["DYNAMODB_TABLE"]
SAGEMAKER_ENDPOINT_NAME = os.environ.get("SAGEMAKER_ENDPOINT_NAME", "")

# 모듈 레벨 초기화: Lambda 컨테이너 재사용 시 연결 재활용
bedrock           = boto3.client("bedrock-runtime", region_name="us-east-1")
dynamodb          = boto3.resource("dynamodb")
sagemaker_runtime = boto3.client("sagemaker-runtime", region_name="us-east-1")
table             = dynamodb.Table(DYNAMODB_TABLE)

LEVEL_MAP = {
    "LOW":    "BEGINNER",
    "MEDIUM": "INTERMEDIATE",
    "HIGH":   "ADVANCED",
}

# bedrock.py와 동일한 시스템 프롬프트 (f-string 아님 — 의도적)
SYSTEM_PROMPT = """
    # Role
    너는 서퍼의 생명을 책임지는 '단호하고 까칠한' 전문 서핑 코치야.
    제공된 데이터를 바탕으로 실력에 맞는 조언을 한국어와 영어로 각각 제공해야 해.

    # Step-by-Step Logic (반드시 이 순서로 사고할 것)
    1. **[Level Check]**: <data>의 서핑 레벨을 먼저 인지할 것.
    2. **[Critical Safety]**: 풍속 10m/s 이상, 수온 5°C 이하 -> 무조건 '입수 불가' 선언.
    3. **[휴식 권고]**: 파도 0.3m 이하(장판) OR 서핑 점수 40점 미만 OR 파도 주기 < 7 -> "서핑하기엔 너무 잔잔하다"거나 "다른 날에 가라"고 조언.
    4. **[Level-Specific Evaluation]**: 사용자의 서핑 레벨에 따라 아래 구간을 엄격히 적용할 것.
        - **BEGINNER**: [0.5 <= waveHeight <= 1.1] 이면 무조건 '적정'. 1.1 초과면 무조건 '위험'.
        - **INTERMEDIATE**: [1.1 < waveHeight <= 1.7] 이면 무조건 '적정'. 1.1 이하면 '시시함'. 1.7 초과면 '위험'.
        - **ADVANCED**: [waveHeight >= 1.7] 이면 무조건 '적정'. 1.7 미만이면 무조건 '시시함'.

    # Writing logic (전 레벨 공통 절대 원칙)
    1. **Internal Calculus (드러내지 않는 계산)**:
        - 입력된 파도 높이를 사용자의 레벨 임계값에 대입하여 '적정/시시함/위험' 중 하나의 상태를 먼저 확정할 것.
        - 확정된 상태에 따라 아래 '상태 묘사' 단계로 넘어갈 것.

    2. **Visual Description (숫자 대신 풍경으로 말하기)**:
        - **숫자 사용 엄금**: 문장의 어디에도 '2.5m', '10s' 같은 숫자를 쓰지 마.
        - **비유적 치환**: 숫자를 아래와 같은 서퍼의 언어로 치환해.
            - 1.0m 이하 -> '무릎~허리 사이즈', '아기자기한 파도'
            - 1.5m ~ 2.0m -> '어깨~머리 사이즈', '묵직한 너울'
            - 2.5m 이상 -> '오버헤드', '집어삼킬 듯한 매시브한 파도'
        - **복합 컨디션 반영**: 주기(Period)와 바람(Wind)을 형용사로 사용해.

    3. **Persona & Voice**:
        - **말투**: 한국어는 "~해요"체, 영어는 단호하고 전문적인 코치 스타일로.
        - **권장어**: '연습하기 딱이에요', '입수해봤자 고생입니다', '패들링만 하다 끝날 바다', '실력 발휘하기 최적'.
        - **절대 원칙**: 한국어 답변에 '초급/중급/상급' 외의 모든 영어(Advanced, Intermediate 등) 및 음차 표현 사용 금지.

    4. **Output Integrity**:
        - 위험 요소(강풍, 저수온, 기량 미달)가 하나라도 있으면 문장 전체를 경고 톤으로 유지할 것. (모순된 칭찬 금지)

    # Logic Reference (Do NOT copy sentences, follow the logic only)
    - [ADVANCED / H < 1.7m] -> Evaluation: Trivial | Tone: Cold
    - [INTERMEDIATE / 1.1m < H <= 1.7m] -> Evaluation: Suitable | Tone: Analytical
    - [BEGINNER / H > 1.1m] -> Evaluation: Dangerous | Tone: Alarm

    # Terminology Mapping (용어 강제 지정)
    - 사용자의 레벨 및 모든 조언에서 아래 한국어 단어만 사용할 것:
        - BEGINNER -> 초급
        - INTERMEDIATE -> 중급
        - ADVANCED -> 상급
    - '어드밴스드', '인터미디에이트' 등 영어를 한글로 소리 나는 대로 적는 행위(음차)를 엄격히 금지함.

    # Keywords to use for variety:
    - 장판, 호수, 시시함, 에너지 부족, 연습에 도움되지 않음, 휴식 권고.
    - 무릎 높이, 허리 높이, 가슴 높이, 묵직한 너울, 훈련하기에 적당함.

    # Output Style
    - 반드시 순수한 JSON 형식으로만 답변하고, ```json 같은 마크다운 태그는 절대 쓰지 마.
      { "ko": "한국어 조언", "en": "English advice" }
    - 키 이름은 반드시 소문자 "ko", "en"을 사용해.
    - 한국어/영어 모두 공백 포함 70자 이내, 명확한 문장으로 결론 맺기.
    - 인사나 감탄사 없이 바로 본론만 말해.
    - 언어 섞어서 사용 금지.

    위 가이드에 따라 모순 없는 한 줄 평을 작성해줘:
    """


def _surf_score_from_sagemaker(conditions, geo, surf_timestamp):
    """
    SageMaker 실시간 엔드포인트에서 surf score(0-100) 조회.
    derivedMetrics가 없을 때 fallback으로 사용.

    Feature order must match preprocess.py output (27 features).
    Available: wave_height, wave_period, wind_speed_10m, sea_surface_temperature, lat, lng.
    나머지 피처는 0으로 설정.
    """
    if not SAGEMAKER_ENDPOINT_NAME:
        return None

    wh  = float(conditions.get("waveHeight") or 0)
    wp  = float(conditions.get("wavePeriod") or 0)
    ws  = float(conditions.get("windSpeed") or 0)
    wt  = float(conditions.get("waterTemperature") or 0)
    lat = float(geo.get("lat") or 0) if geo else 0.0
    lng = float(geo.get("lng") or 0) if geo else 0.0

    try:
        hour = int(surf_timestamp[11:13])
    except Exception:
        hour = 12

    # 27-feature vector: 가용 피처 우선, 나머지는 0 (preprocess.py 순서 일치 필요)
    features = [
        wh,                                        # wave_height
        wp,                                        # wave_period
        0.0,                                       # swell_wave_height
        0.0,                                       # swell_wave_period
        wt,                                        # sea_surface_temperature
        0.0,                                       # ocean_current_velocity
        ws,                                        # wind_speed_10m
        ws * 1.3,                                  # wind_gusts_10m (estimate)
        0.0,                                       # temperature_2m
        0.0,                                       # wave_direction_sin
        1.0,                                       # wave_direction_cos
        0.0,                                       # swell_wave_direction_sin
        1.0,                                       # swell_wave_direction_cos
        0.0,                                       # wind_direction_10m_sin
        1.0,                                       # wind_direction_10m_cos
        wh * wp * wp,                              # wave_power
        0.0,                                       # swell_power
        ws / max(wh, 0.1),                         # wind_wave_ratio
        1.3,                                       # gust_factor (estimate)
        wh / max(wp * wp, 0.01),                   # wave_steepness
        lat,                                       # lat
        lng,                                       # lon
        abs(lat),                                  # abs_lat
        math.sin(2 * math.pi * hour / 24),         # hour_sin
        math.cos(2 * math.pi * hour / 24),         # hour_cos
        0.0,                                       # day_of_week_sin
        1.0,                                       # day_of_week_cos
    ]

    csv_line = ",".join(f"{f:.6f}" for f in features)
    try:
        resp = sagemaker_runtime.invoke_endpoint(
            EndpointName=SAGEMAKER_ENDPOINT_NAME,
            ContentType="text/csv",
            Body=csv_line,
        )
        # XGBoost multi:softmax: class label 0-4 → score 0-100
        class_label = int(float(resp["Body"].read().decode("utf-8").strip()))
        return class_label * 25
    except Exception as e:
        print(f"[bedrock_summary] SageMaker error: {e}")
        return None


def handler(event, context):
    location_id    = event["location_id"]
    surf_timestamp = event["surf_timestamp"]
    # surfing_level     = LEVEL_MAP.get(event.get("surfing_level", "LOW"), "BEGINNER")
    surfing_level = event.get("surfing_level", "BEGINNER").upper()
    if surfing_level not in ("BEGINNER", "INTERMEDIATE", "ADVANCED"):
        surfing_level = "BEGINNER"

    # 1. DynamoDB 조회 — camelCase PK/SK (save.py 스키마 기준)
    response = table.get_item(
        Key={"locationId": location_id, "surfTimestamp": surf_timestamp}
    )
    item = response.get("Item", {})

    # 2. 캐시 히트 확인
    cache_attr = f"ai_summary_{surfing_level}"
    if cache_attr in item:
        cached = item[cache_attr]
        try:
            advice = json.loads(cached)
        except (json.JSONDecodeError, TypeError):
            advice = {"ko": str(cached), "en": str(cached)}
        return {"advice": advice, "cache": "hit"}

    # 3. 조건 데이터 추출 — nested conditions (save.py 기준)
    conditions = item.get("conditions", {})
    geo        = item.get("geo", {})

    wh = float(conditions.get("waveHeight") or 0)
    wp = float(conditions.get("wavePeriod") or 0)
    ws = float(conditions.get("windSpeed") or 0)
    wt = float(conditions.get("waterTemperature") or 0)

    # 4. surf score: derivedMetrics 우선, SageMaker 폴백
    derived    = item.get("derivedMetrics", {})
    level_data = derived.get(surfing_level, {})
    if level_data and level_data.get("surfScore") is not None:
        surf_score = float(level_data["surfScore"])
    else:
        surf_score = _surf_score_from_sagemaker(conditions, geo, surf_timestamp) or 0.0

    # 5. user_data f-string (bedrock.py와 동일 구조)
    user_data = f"""
    <data>
    - 파도 높이: {wh}m
    - 파도 주기: {wp}s
    - 풍속: {ws}m/s
    - 수온: {wt}°C
    - 서핑 점수: {surf_score}
    - 서핑 레벨: {surfing_level}
    </data>
    """

    # 6. Bedrock 호출 (system_prompt + user_data 분리 구조)
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "system": SYSTEM_PROMPT,
        "max_tokens": 200,
        "temperature": 0.8,
        "top_p": 0.9,
        "top_k": 100,
        "messages": [{"role": "user", "content": [{"type": "text", "text": user_data}]}],
    }
    bedrock_response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        body=json.dumps(payload),
    )
    full_content = json.loads(bedrock_response["body"].read())["content"][0]["text"].strip()

    # JSON 추출
    start  = full_content.find("{")
    end    = full_content.rfind("}") + 1
    advice = json.loads(full_content[start:end])

    # 7. DynamoDB에 캐시 저장 (JSON 문자열로 저장)
    table.update_item(
        Key={"locationId": location_id, "surfTimestamp": surf_timestamp},
        UpdateExpression=f"SET {cache_attr} = :s",
        ExpressionAttributeValues={":s": json.dumps(advice, ensure_ascii=False)},
    )

    return {"advice": advice, "cache": "miss"}
