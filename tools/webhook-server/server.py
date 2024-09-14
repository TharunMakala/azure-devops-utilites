"""
Azure DevOps Webhook Server

Receives webhook events from Azure DevOps and routes them to configured
notification channels (Slack, Teams, email) with filtering and formatting.
"""

import hashlib
import hmac
import json
import logging
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional

import uvicorn
from fastapi import FastAPI, HTTPException, Header, Request
from pydantic import BaseModel, Field

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("webhook-server")

app = FastAPI(
    title="Azure DevOps Webhook Server",
    version="1.0.0",
    description="Receives and routes Azure DevOps webhook events",
)


class EventType(str, Enum):
    BUILD_COMPLETED = "build.complete"
    RELEASE_CREATED = "ms.vss-release.release-created-event"
    RELEASE_COMPLETED = "ms.vss-release.deployment-completed-event"
    WORK_ITEM_CREATED = "workitem.created"
    WORK_ITEM_UPDATED = "workitem.updated"
    PR_CREATED = "git.pullrequest.created"
    PR_UPDATED = "git.pullrequest.updated"
    PR_MERGED = "git.pullrequest.merged"
    CODE_PUSHED = "git.push"


class WebhookPayload(BaseModel):
    subscription_id: Optional[str] = Field(None, alias="subscriptionId")
    notification_id: Optional[int] = Field(None, alias="notificationId")
    event_type: str = Field(..., alias="eventType")
    message: Optional[dict] = None
    resource: dict = {}
    created_date: Optional[str] = Field(None, alias="createdDate")


@dataclass
class NotificationConfig:
    slack_webhook_url: Optional[str] = None
    teams_webhook_url: Optional[str] = None
    email_smtp_host: Optional[str] = None
    email_from: Optional[str] = None
    email_to: list[str] = field(default_factory=list)
    filter_projects: list[str] = field(default_factory=list)
    filter_events: list[str] = field(default_factory=list)
    min_severity: str = "info"


config = NotificationConfig(
    slack_webhook_url=os.getenv("SLACK_WEBHOOK_URL"),
    teams_webhook_url=os.getenv("TEAMS_WEBHOOK_URL"),
    filter_projects=os.getenv("FILTER_PROJECTS", "").split(",") if os.getenv("FILTER_PROJECTS") else [],
    filter_events=os.getenv("FILTER_EVENTS", "").split(",") if os.getenv("FILTER_EVENTS") else [],
)

WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "")

# In-memory event store for recent events
recent_events: list[dict] = []
MAX_RECENT_EVENTS = 500


def verify_signature(payload: bytes, signature: str) -> bool:
    """Verify HMAC signature from Azure DevOps webhook."""
    if not WEBHOOK_SECRET:
        return True
    expected = hmac.new(
        WEBHOOK_SECRET.encode(), payload, hashlib.sha1
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def format_build_event(resource: dict) -> dict:
    """Format build completion event for notification."""
    result = resource.get("result", "unknown")
    definition = resource.get("definition", {})
    severity = "error" if result == "failed" else "info"

    return {
        "title": f"Build {result.upper()}: {definition.get('name', 'Unknown')}",
        "severity": severity,
        "fields": {
            "Pipeline": definition.get("name"),
            "Build Number": resource.get("buildNumber"),
            "Result": result,
            "Requested By": resource.get("requestedFor", {}).get("displayName"),
            "Branch": resource.get("sourceBranch", "").replace("refs/heads/", ""),
            "Duration": _calculate_duration(
                resource.get("startTime"), resource.get("finishTime")
            ),
        },
        "url": resource.get("_links", {}).get("web", {}).get("href"),
        "color": "#ff0000" if result == "failed" else "#36a64f",
    }


def format_pr_event(resource: dict, event_type: str) -> dict:
    """Format pull request event for notification."""
    action = event_type.split(".")[-1]
    pr_title = resource.get("title", "Untitled PR")
    repo = resource.get("repository", {}).get("name", "Unknown")

    return {
        "title": f"PR {action}: {pr_title}",
        "severity": "info",
        "fields": {
            "Repository": repo,
            "Author": resource.get("createdBy", {}).get("displayName"),
            "Source": resource.get("sourceRefName", "").replace("refs/heads/", ""),
            "Target": resource.get("targetRefName", "").replace("refs/heads/", ""),
            "Reviewers": ", ".join(
                r.get("displayName", "")
                for r in resource.get("reviewers", [])
            ),
            "Status": resource.get("status"),
        },
        "url": resource.get("url"),
        "color": "#0078d4",
    }


def format_workitem_event(resource: dict, event_type: str) -> dict:
    """Format work item event for notification."""
    fields = resource.get("fields", {})
    action = "created" if "created" in event_type else "updated"

    return {
        "title": f"Work Item {action}: {fields.get('System.Title', 'Untitled')}",
        "severity": "info",
        "fields": {
            "Type": fields.get("System.WorkItemType"),
            "State": fields.get("System.State"),
            "Assigned To": fields.get("System.AssignedTo", {}).get("displayName")
            if isinstance(fields.get("System.AssignedTo"), dict)
            else fields.get("System.AssignedTo"),
            "Priority": fields.get("Microsoft.VSTS.Common.Priority"),
            "Area Path": fields.get("System.AreaPath"),
        },
        "url": resource.get("_links", {}).get("html", {}).get("href"),
        "color": "#ffa500",
    }


def _calculate_duration(start: Optional[str], end: Optional[str]) -> str:
    """Calculate human-readable duration between two ISO timestamps."""
    if not start or not end:
        return "N/A"
    try:
        start_dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        end_dt = datetime.fromisoformat(end.replace("Z", "+00:00"))
        delta = end_dt - start_dt
        minutes, seconds = divmod(int(delta.total_seconds()), 60)
        hours, minutes = divmod(minutes, 60)
        if hours > 0:
            return f"{hours}h {minutes}m {seconds}s"
        return f"{minutes}m {seconds}s"
    except (ValueError, TypeError):
        return "N/A"


async def send_slack_notification(message: dict) -> None:
    """Send formatted notification to Slack."""
    import httpx

    if not config.slack_webhook_url:
        return

    slack_payload = {
        "attachments": [
            {
                "color": message.get("color", "#0078d4"),
                "title": message["title"],
                "fields": [
                    {"title": k, "value": str(v or "N/A"), "short": True}
                    for k, v in message.get("fields", {}).items()
                ],
                "footer": "Azure DevOps Webhook Server",
                "ts": int(datetime.now().timestamp()),
            }
        ]
    }

    if message.get("url"):
        slack_payload["attachments"][0]["title_link"] = message["url"]

    async with httpx.AsyncClient() as client:
        resp = await client.post(config.slack_webhook_url, json=slack_payload)
        if resp.status_code != 200:
            logger.error("Slack notification failed: %d %s", resp.status_code, resp.text)


async def send_teams_notification(message: dict) -> None:
    """Send formatted notification to Microsoft Teams."""
    import httpx

    if not config.teams_webhook_url:
        return

    teams_payload = {
        "@type": "MessageCard",
        "themeColor": message.get("color", "0078d4").lstrip("#"),
        "summary": message["title"],
        "sections": [
            {
                "activityTitle": message["title"],
                "facts": [
                    {"name": k, "value": str(v or "N/A")}
                    for k, v in message.get("fields", {}).items()
                ],
            }
        ],
    }

    if message.get("url"):
        teams_payload["potentialAction"] = [
            {
                "@type": "OpenUri",
                "name": "View in Azure DevOps",
                "targets": [{"os": "default", "uri": message["url"]}],
            }
        ]

    async with httpx.AsyncClient() as client:
        resp = await client.post(config.teams_webhook_url, json=teams_payload)
        if resp.status_code != 200:
            logger.error("Teams notification failed: %d %s", resp.status_code, resp.text)


@app.post("/webhook")
async def handle_webhook(
    request: Request,
    x_hub_signature: Optional[str] = Header(None, alias="X-Hub-Signature"),
):
    """Main webhook endpoint for Azure DevOps events."""
    body = await request.body()

    if WEBHOOK_SECRET and x_hub_signature:
        if not verify_signature(body, x_hub_signature.replace("sha1=", "")):
            raise HTTPException(status_code=401, detail="Invalid signature")

    try:
        payload = WebhookPayload.model_validate_json(body)
    except Exception as e:
        logger.error("Failed to parse payload: %s", e)
        raise HTTPException(status_code=400, detail="Invalid payload")

    event_type = payload.event_type
    resource = payload.resource
    logger.info("Received event: %s (notification: %s)", event_type, payload.notification_id)

    # Apply event filter
    if config.filter_events and event_type not in config.filter_events:
        logger.debug("Event %s filtered out", event_type)
        return {"status": "filtered"}

    # Format based on event type
    if event_type == EventType.BUILD_COMPLETED:
        message = format_build_event(resource)
    elif event_type in (EventType.PR_CREATED, EventType.PR_UPDATED, EventType.PR_MERGED):
        message = format_pr_event(resource, event_type)
    elif event_type in (EventType.WORK_ITEM_CREATED, EventType.WORK_ITEM_UPDATED):
        message = format_workitem_event(resource, event_type)
    else:
        message = {
            "title": f"Event: {event_type}",
            "severity": "info",
            "fields": {"Event": event_type},
            "color": "#808080",
        }

    # Store in recent events
    recent_events.append(
        {
            "timestamp": datetime.now().isoformat(),
            "event_type": event_type,
            "message": message,
        }
    )
    if len(recent_events) > MAX_RECENT_EVENTS:
        recent_events.pop(0)

    # Send notifications
    await send_slack_notification(message)
    await send_teams_notification(message)

    return {"status": "processed", "event_type": event_type}


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "version": "1.0.0",
        "events_processed": len(recent_events),
    }


@app.get("/events")
async def get_recent_events(limit: int = 50, event_type: Optional[str] = None):
    """Return recent webhook events."""
    events = recent_events
    if event_type:
        events = [e for e in events if e["event_type"] == event_type]
    return {"count": len(events[-limit:]), "events": events[-limit:]}


if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", "8080")),
        reload=os.getenv("ENV", "production") == "development",
        log_level="info",
    )
