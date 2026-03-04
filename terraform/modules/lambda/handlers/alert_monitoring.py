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
import urllib.parse
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
COLOR_SUCCESS = 0x57F287   # green    – deployment succeeded
COLOR_FAILURE = 0xED4245   # red      – deployment failed


_STATUS_META = {
    "triggered": {
        "color":       COLOR_DEPLOY,
        "title":       ":rocket: Deployment triggered — `{branch}`",
        "description": "A push to **{branch}** has started the EKS deployment pipeline.",
    },
    "success": {
        "color":       COLOR_SUCCESS,
        "title":       ":white_check_mark: Deployment succeeded — `{branch}`",
        "description": "The EKS deployment for **{branch}** completed successfully.",
    },
    "failure": {
        "color":       COLOR_FAILURE,
        "title":       ":x: Deployment failed — `{branch}`",
        "description": "The EKS deployment for **{branch}** encountered an error. Check the logs.",
    },
}


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


# ── CloudWatch console URL helpers ───────────────────────────────────────────

def _cloudwatch_alarm_url(region_code: str, alarm_name: str) -> str:
    encoded = urllib.parse.quote(alarm_name, safe="")
    return (
        f"https://{region_code}.console.aws.amazon.com/cloudwatch/home"
        f"?region={region_code}#alarmsV2:alarm/{encoded}"
    )

def _cloudwatch_logs_url(region_code: str, log_group: str) -> str:
    encoded = urllib.parse.quote(log_group, safe="")
    return (
        f"https://{region_code}.console.aws.amazon.com/cloudwatch/home"
        f"?region={region_code}#logsV2:log-groups/log-group/{encoded}"
    )


# ── Message builders ──────────────────────────────────────────────────────────

def _build_cloudwatch_embed(msg: dict) -> dict:
    """
    Build a Discord embed from a CloudWatch Alarm SNS message.

    CloudWatch alarm states: ALARM | OK | INSUFFICIENT_DATA
    """
    alarm_name  = msg.get("AlarmName", "Unknown Alarm")
    alarm_arn   = msg.get("AlarmArn", "")
    state       = msg.get("NewStateValue", "UNKNOWN")
    reason      = msg.get("NewStateReason", "")
    region      = msg.get("Region", "us-east-1")
    change_time = msg.get("StateChangeTime", "")
    trigger     = msg.get("Trigger", {})
    metric_name = trigger.get("MetricName", "")
    namespace   = trigger.get("Namespace", "")
    threshold   = trigger.get("Threshold", "")
    period      = trigger.get("Period", "")
    dimensions  = trigger.get("Dimensions", [])

    # ARN에서 API 리전 코드 추출 (Region 필드는 "US East (N. Virginia)" 형식이라 URL 사용 불가)
    # arn:aws:cloudwatch:us-east-1:123456789012:alarm:AlarmName
    arn_parts   = alarm_arn.split(":")
    region_code = arn_parts[3] if len(arn_parts) > 3 and arn_parts[3] else "us-east-1"

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

    # 콘솔 링크
    alarm_url = _cloudwatch_alarm_url(region_code, alarm_name)
    links = [f"[View Alarm]({alarm_url})"]

    if namespace == "AWS/Lambda":
        for dim in dimensions:
            if dim.get("name") == "FunctionName":
                log_group = f"/aws/lambda/{dim['value']}"
                links.append(f"[View Logs]({_cloudwatch_logs_url(region_code, log_group)})")
                break
    elif namespace == "awaves/Application":
        log_group = "/aws/eks/awaves-dev/application"
        links.append(f"[View Logs]({_cloudwatch_logs_url(region_code, log_group)})")

    fields.append({"name": "Links", "value": " | ".join(links), "inline": False})

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

    Expected keys: type, status, branch, commit, actor, repo
    status: "triggered" | "success" | "failure"  (defaults to "triggered")
    """
    status      = msg.get("status", "triggered")
    branch      = msg.get("branch", "main")
    commit_full = msg.get("commit", "")
    commit      = commit_full[:7]
    actor       = msg.get("actor", "unknown")
    repo        = msg.get("repo", "AWSCEAN/awaves-agent")
    ts          = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    meta = _STATUS_META.get(status, _STATUS_META["triggered"])

    commit_url  = f"https://github.com/{repo}/commit/{commit_full}"
    actions_url = f"https://github.com/{repo}/actions"
    links       = [f"[View Commit]({commit_url})", f"[View Actions]({actions_url})"]

    return {
        "title":       meta["title"].format(branch=branch),
        "description": meta["description"].format(branch=branch),
        "color":       meta["color"],
        "fields": [
            {"name": "Repository", "value": repo,               "inline": True},
            {"name": "Actor",      "value": actor,              "inline": True},
            {"name": "Commit",     "value": f"`{commit}`",      "inline": True},
            {"name": "Links",      "value": " | ".join(links),  "inline": False},
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
