"""
Lambda: awaves-dev-alert-monitoring

Receives SNS messages from awaves-dev-alerts topic and routes them to
the appropriate Discord channel based on message type:

  CloudWatch Alarm  → DISCORD_ERROR_WEBHOOK_URL   (errors / recoveries)
  Deployment notice → DISCORD_DEPLOY_WEBHOOK_URL  (push to main triggered)

Environment variables required:
  DISCORD_ERROR_WEBHOOK_URL   — Discord #errors channel webhook
  DISCORD_DEPLOY_WEBHOOK_URL  — Discord #deployments channel webhook
"""

import json
import logging
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

DISCORD_ERROR_WEBHOOK_URL  = os.environ["DISCORD_ERROR_WEBHOOK_URL"]
DISCORD_DEPLOY_WEBHOOK_URL = os.environ["DISCORD_DEPLOY_WEBHOOK_URL"]

# Discord embed colours (decimal)
COLOR_ERROR   = 15158332   # #E74C3C red
COLOR_OK      = 3066993    # #2ECC71 green
COLOR_DEPLOY  = 3447003    # #3498DB blue
COLOR_WARNING = 16776960   # #FFFF00 yellow


# ── Discord helper ────────────────────────────────────────────────────────────

def _send_discord(webhook_url: str, embed: dict) -> None:
    """POST a single embed to a Discord webhook."""
    payload = json.dumps({"embeds": [embed]}).encode("utf-8")
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            logger.info("Discord response: %s", resp.status)
    except urllib.error.HTTPError as e:
        logger.error("Discord HTTP error %s: %s", e.code, e.read())
    except Exception as e:
        logger.error("Discord send failed: %s", e)


# ── Message builders ──────────────────────────────────────────────────────────

def _build_cloudwatch_embed(msg: dict) -> dict:
    """
    Build a Discord embed from a CloudWatch Alarm SNS message.

    CloudWatch alarm states: ALARM | OK | INSUFFICIENT_DATA
    """
    alarm_name  = msg.get("AlarmName", "Unknown Alarm")
    state       = msg.get("NewStateValue", "UNKNOWN")
    reason      = msg.get("NewStateReason", "")
    region      = msg.get("Region", "us-east-1")
    change_time = msg.get("StateChangeTime", "")
    trigger     = msg.get("Trigger", {})
    metric_name = trigger.get("MetricName", "")
    namespace   = trigger.get("Namespace", "")
    threshold   = trigger.get("Threshold", "")
    period      = trigger.get("Period", "")

    if state == "ALARM":
        color = COLOR_ERROR
        title = f":rotating_light: ALARM — {alarm_name}"
    elif state == "OK":
        color = COLOR_OK
        title = f":white_check_mark: RECOVERED — {alarm_name}"
    else:
        color = COLOR_WARNING
        title = f":warning: {state} — {alarm_name}"

    try:
        dt = datetime.fromisoformat(change_time.replace("Z", "+00:00"))
        ts = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
    except Exception:
        ts = change_time

    fields = []
    if metric_name:
        fields.append({"name": "Metric",    "value": f"`{namespace}/{metric_name}`", "inline": True})
    if threshold:
        fields.append({"name": "Threshold", "value": str(threshold),                "inline": True})
    if period:
        fields.append({"name": "Period",    "value": f"{period}s",                  "inline": True})
    if region:
        fields.append({"name": "Region",    "value": region,                        "inline": True})

    return {
        "title":       title,
        "description": reason[:2000] if reason else "No details available.",
        "color":       color,
        "fields":      fields,
        "footer":      {"text": f"CloudWatch • {ts}"},
    }


def _build_deployment_embed(msg: dict) -> dict:
    """
    Build a Discord embed from a deployment notification published by
    the GitHub Actions deploy.yml workflow.

    Expected keys: type, branch, commit, actor, repo
    """
    branch = msg.get("branch", "main")
    commit = msg.get("commit", "")[:7]
    actor  = msg.get("actor", "unknown")
    repo   = msg.get("repo", "AWSCEAN/awaves-agent")
    ts     = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    return {
        "title":       f":rocket: Deployment triggered — `{branch}`",
        "description": f"A push to **{branch}** has started the EKS deployment pipeline.",
        "color":       COLOR_DEPLOY,
        "fields": [
            {"name": "Repository", "value": repo,          "inline": True},
            {"name": "Actor",      "value": actor,         "inline": True},
            {"name": "Commit",     "value": f"`{commit}`", "inline": True},
        ],
        "footer": {"text": f"GitHub Actions • {ts}"},
    }


# ── Handler ───────────────────────────────────────────────────────────────────

def handler(event, context):
    for record in event.get("Records", []):
        sns_message_str = record.get("Sns", {}).get("Message", "{}")

        try:
            msg = json.loads(sns_message_str)
        except json.JSONDecodeError:
            logger.warning("Non-JSON SNS message: %s", sns_message_str)
            continue

        if msg.get("type") == "deployment":
            embed       = _build_deployment_embed(msg)
            webhook_url = DISCORD_DEPLOY_WEBHOOK_URL
        elif "AlarmName" in msg:
            embed       = _build_cloudwatch_embed(msg)
            webhook_url = DISCORD_ERROR_WEBHOOK_URL
        else:
            # Unknown shape — send to error channel as a fallback
            embed = {
                "title":       ":bell: Unknown alert",
                "description": sns_message_str[:2000],
                "color":       COLOR_WARNING,
            }
            webhook_url = DISCORD_ERROR_WEBHOOK_URL

        _send_discord(webhook_url, embed)

    return {"status": "ok"}
