"""
Lambda: Alert ML Pipeline
Triggered when SageMaker model evaluation results in "Bad" quality.
Publishes alert to SNS topic for data scientist notification.

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
  Publishes to SNS alerts topic.
  Returns: { "status": "success", "notified": true }
"""

import json
import os

import boto3

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

sns = boto3.client("sns")


def handler(event, context):
    evaluation_result = event.get("evaluation_result", "unknown")
    model_version = event.get("model_version", "unknown")
    metrics = event.get("metrics", {})

    if evaluation_result.lower() != "bad":
        return {
            "status": "skipped",
            "reason": f"Evaluation result is '{evaluation_result}', not 'bad'.",
            "notified": False,
        }

    # Build alert message
    message = {
        "alert_type": "ML_PIPELINE_BAD_EVALUATION",
        "environment": ENVIRONMENT,
        "model_version": model_version,
        "evaluation_result": evaluation_result,
        "metrics": metrics,
        "action_required": "Review model training results and retrain if necessary.",
    }

    subject = f"[awaves-{ENVIRONMENT}] ML Pipeline Alert: Bad Model Evaluation"

    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN not configured. Logging only.")
        print(json.dumps(message, indent=2))
        return {"status": "success", "notified": False, "reason": "no_sns_topic"}

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=subject[:100],
        Message=json.dumps(message, indent=2),
    )

    return {
        "status": "success",
        "notified": True,
        "model_version": model_version,
    }
