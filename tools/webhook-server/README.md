# Azure DevOps Webhook Server

FastAPI server that receives webhook events from Azure DevOps and routes notifications to Slack and Microsoft Teams.

## Supported Events

- Build completed (success/failure)
- Pull request created/updated/merged
- Work item created/updated
- Release deployment events
- Code push events

## Setup

```bash
cd tools/webhook-server
pip install -r requirements.txt

export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export TEAMS_WEBHOOK_URL="https://outlook.office.com/webhook/..."
export WEBHOOK_SECRET="your-shared-secret"

python server.py
```

## Docker

```bash
docker build -t webhook-server .
docker run -p 8080:8080 \
  -e SLACK_WEBHOOK_URL="..." \
  -e WEBHOOK_SECRET="..." \
  webhook-server
```

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/webhook` | POST | Receive Azure DevOps events |
| `/health` | GET | Health check |
| `/events` | GET | List recent events |
