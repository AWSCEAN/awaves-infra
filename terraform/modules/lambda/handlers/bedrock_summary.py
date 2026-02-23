"""
Lambda: Bedrock Summary

DynamoDB에서 서핑 조건을 읽고 Bedrock(Claude Haiku)으로 한 줄 요약을 생성한다.
동일 요청에 대해 DynamoDB 아이템에 결과를 캐싱한다.

Input event:
  {
    "location_id":    "33.44#-94.04",
    "surf_timestamp": "2026-01-28T06:00:00Z",
    "user_level":     "LOW"  # LOW | MEDIUM | HIGH (Aurora users.user_level)
  }

Output:
  { "summary": "파도 적당하고 주기도 충분해요...", "cache": "hit" | "miss" }

Cache strategy:
  DynamoDB UpdateItem으로 surf-data 아이템에 ai_summary_{LEVEL} 속성 추가.
  3시간 배치 주기로 신규 아이템이 생성되므로 별도 TTL 불필요.
"""
import json
import os
import boto3

BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID",
    "us.anthropic.claude-3-5-haiku-20241022-v1:0"
)
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]

# 모듈 레벨 초기화: Lambda 컨테이너 재사용 시 연결 재활용
bedrock  = boto3.client("bedrock-runtime", region_name="us-east-1")
dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(DYNAMODB_TABLE)

LEVEL_MAP = {
    "LOW":    "BEGINNER",
    "MEDIUM": "INTERMEDIATE",
    "HIGH":   "ADVANCED",
}


def _build_prompt(wave_height, wave_period, wind_speed, water_temp,
                  surf_score, user_level):
    return f"""
    # Role
    너는 서퍼의 생명을 책임지는 '단호하고 까칠한' 전문 서핑 코치야.
    제공된 데이터를 바탕으로 실력에 맞는 조언을 제공해야 해.

    <data>
    - 파도 높이: {wave_height}m
    - 파도 주기: {wave_period}s
    - 풍속: {wind_speed}m/s
    - 수온: {water_temp}°C
    - 서핑 점수: {surf_score}
    - 서핑 레벨: {user_level}
    </data>

    # Critical Safety Rules (최우선 준수)
    1. **[위험: 절대 금지]** - "위험해요", "안전을 위해 참으세요" 등 다양하게 표현
        - 수온 5°C 이하 OR 풍속 10m/s 이상 OR 레벨 대비 너무 높은 파도.
        - 이때는 '안전'과 '생동감 있는 경고'가 최우선.

    2. **[부적합: 휴식 권고]** - "파도가 아쉬워요", "다음에 타요" 등 다양하게 표현
        - 파도 0.3m 미만(장판) OR 서핑 점수 40점 미만.
        - 이때는 위험하다고 겁주지 말고, "서핑하기엔 너무 잔잔하다"거나 "다른 날에 가라"고 현실적으로 조언.

    3. **레벨별 주관적 체감 지수**:
        - 사용자의 서핑 레벨([{user_level}])에 따라 파도를 평가해서 조언할 것.
        - 레벨별 적합한 파도 높이
            - BEGINNER: 0.5m~1.1m (1.1m 초과는 초보에게 '매우 위험')
            - INTERMEDIATE: 1.1m~1.7m
            - ADVANCED: 1.7m 이상 (1.7m 이하는 시시할 수 있음)

    4. **주기 분석**: 파도가 적당해도 주기가 7s 미만이면 "힘없는 너울이라 재미없다"는 경고를 덧붙여.

    # Writing logic
    - **모순 금지**: 위험 요소(강풍, 저수온, 기량부족, 파도높이 부적절)가 하나라도 있으면 절대 "즐겁게 연습하라"거나 "안전하게 입수하라"는 긍정형 문장을 쓰지 마.
    - **핵심 요약**: 여러 위험이 겹치면 모든 위험을 합쳐서 말해.
        - 예시 : "파도도 없고 바람까지 위험하니 서핑 불가!"
    - 현재 사용자의 레벨([{user_level}])과 맞지 않는 타 레벨 전용 조언이나 단어를 절대 언급하지 마.

    # Output Style
    - 반드시 공백 포함 **70자 이내** 한국어.
    - 말투: "~해요"체를 쓰되, 위험할 땐 단호하게, 장판일 땐 아쉬워하듯이.
    - 수치(숫자)는 쓰지 말고 상태 위주로 묘사해.
    - 인사나 감탄사 없이 바로 본론만 말해.
    - 모든 답변은 한국어로만 작성하고 명확한 문장으로 결론을 맺기.

    위 가이드에 따라 모순 없는 한 줄 평을 작성해줘:
    """


def handler(event, context):
    location_id    = event["location_id"]
    surf_timestamp = event["surf_timestamp"]
    user_level     = LEVEL_MAP.get(event.get("user_level", "LOW"), "BEGINNER")

    # 1. DynamoDB 조회 (서핑 조건 + 기존 캐시 동시 확인)
    response = table.get_item(
        Key={"LocationId": location_id, "SurfTimestamp": surf_timestamp}
    )
    item = response.get("Item", {})

    # 2. 캐시 히트 확인
    cache_attr = f"ai_summary_{user_level}"
    if cache_attr in item:
        return {"summary": item[cache_attr], "cache": "hit"}

    # 3. DynamoDB 실제 조건값 추출 (snake_case 스키마)
    wave_height = float(item.get("wave_height", 0))
    wave_period = float(item.get("wave_period", 0))
    wind_speed  = float(item.get("wind_speed_10m", 0))
    water_temp  = float(item.get("sea_surface_temperature", 0))
    # rating_value(0-5) → surf_score(0-100) 변환
    surf_score  = round(float(item.get("rating_value", 2.5)) * 20, 1)

    # 4. Bedrock 호출 (STS 없음 - Lambda 실행 역할 자동 사용)
    prompt = _build_prompt(
        wave_height, wave_period, wind_speed, water_temp, surf_score, user_level
    )
    payload = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 150,
        "temperature": 0.8,
        "top_p": 0.9,
        "top_k": 100,
        "messages": [{"role": "user", "content": [{"type": "text", "text": prompt}]}],
    }
    bedrock_response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        body=json.dumps(payload),
    )
    summary = json.loads(bedrock_response["body"].read())["content"][0]["text"].strip()

    # 5. DynamoDB에 캐시 저장
    table.update_item(
        Key={"LocationId": location_id, "SurfTimestamp": surf_timestamp},
        UpdateExpression=f"SET {cache_attr} = :s",
        ExpressionAttributeValues={":s": summary},
    )

    return {"summary": summary, "cache": "miss"}
