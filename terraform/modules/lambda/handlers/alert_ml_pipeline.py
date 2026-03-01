"""
Lambda: Alert ML Pipeline
Triggered when SageMaker model evaluation results in "Bad" quality.
Sends alert directly to Discord webhook for data scientist notification.

Input event:
  {
    "evaluation_result": "bad",
    "model_version": "v1",
    "metrics": {
      "rmse": 0.85,
      "r2": 0.45
    }
  }

Output:
  Posts to Discord webhook.
  Returns: { "status": "success", "notified": true }
"""

import json
import os
import urllib.request

DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")


def handler(event, context):
    # This Lambda is invoked only from the SageMaker Pipeline ElseSteps
    # (QWK below threshold), so evaluation_result defaults to "bad".
    evaluation_result = event.get("evaluation_result", "bad")
    model_version = event.get("model_version", "unknown")
    metrics = event.get("metrics", {})

    if evaluation_result.lower() != "bad":
        return {
            "status": "skipped",
            "reason": f"Evaluation result is '{evaluation_result}', not 'bad'.",
            "notified": False,
        }

    # Build Discord message
    metrics_str = "\n".join(f"  {k}: {v}" for k, v in metrics.items())
    content = (
        f"**[awaves-{ENVIRONMENT}] ML Pipeline Alert: Bad Model Evaluation**\n"
        f"Model Version: `{model_version}`\n"
        f"Metrics:\n{metrics_str}\n"
        f"Action Required: Review model training results and retrain if necessary."
    )

    payload = json.dumps({"content": content}).encode("utf-8")

    if not DISCORD_WEBHOOK_URL:
        print("DISCORD_WEBHOOK_URL not configured. Logging only.")
        print(content)
        return {"status": "success", "notified": False, "reason": "no_webhook_url"}

    req = urllib.request.Request(
        DISCORD_WEBHOOK_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "awaves-alert/1.0",
        },
        method="POST",
    )
    urllib.request.urlopen(req)

    return {
        "status": "success",
        "notified": True,
        "model_version": model_version,
    }
