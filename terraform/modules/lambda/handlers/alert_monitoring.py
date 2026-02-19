"""
Lambda: Alert Monitoring
Receives SNS notifications and forwards to Discord webhook.
Triggered by SNS topic subscription.

Input event: SNS notification (CloudWatch alarm, pipeline alerts, etc.)
Output: Posts message to Discord webhook.
"""

import json
import os
from urllib.request import urlopen, Request

DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")


def _post_to_discord(title, message, color=16711680):
    """Post an embedded message to Discord webhook."""
    if not DISCORD_WEBHOOK_URL:
        print("DISCORD_WEBHOOK_URL not configured. Skipping.")
        return

    payload = {
        "embeds": [{
            "title": f"[{ENVIRONMENT.upper()}] {title}",
            "description": message,
            "color": color,
        }],
    }

    data = json.dumps(payload).encode()
    req = Request(
        DISCORD_WEBHOOK_URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    urlopen(req, timeout=10)


def handler(event, context):
    records = event.get("Records", [])
    processed = 0

    for record in records:
        sns_message = record.get("Sns", {})
        subject = sns_message.get("Subject", "AWS Alert")
        message_body = sns_message.get("Message", "")

        # Try to parse structured message
        try:
            parsed = json.loads(message_body)
            # CloudWatch Alarm format
            if "AlarmName" in parsed:
                title = f"CloudWatch Alarm: {parsed['AlarmName']}"
                message = (
                    f"**State:** {parsed.get('NewStateValue', 'UNKNOWN')}\n"
                    f"**Reason:** {parsed.get('NewStateReason', 'N/A')}\n"
                    f"**Region:** {parsed.get('Region', 'N/A')}"
                )
                color = 16711680 if parsed.get("NewStateValue") == "ALARM" else 65280
            else:
                title = subject
                message = json.dumps(parsed, indent=2)[:2000]
                color = 16776960
        except (json.JSONDecodeError, TypeError):
            title = subject
            message = str(message_body)[:2000]
            color = 16776960

        _post_to_discord(title, message, color)
        processed += 1

    return {
        "status": "success",
        "processed": processed,
    }
