"""Integration tests for the webhook server."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools" / "webhook-server"))

from fastapi.testclient import TestClient
from server import app


@pytest.fixture
def client():
    return TestClient(app)


class TestHealthEndpoint:
    def test_health_check(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data

    def test_health_includes_event_count(self, client):
        response = client.get("/health")
        data = response.json()
        assert "events_processed" in data


class TestWebhookEndpoint:
    def test_build_completed_event(self, client):
        payload = {
            "subscriptionId": "sub-1",
            "notificationId": 1,
            "eventType": "build.complete",
            "resource": {
                "id": 101,
                "result": "succeeded",
                "definition": {"id": 1, "name": "CI-Pipeline"},
                "buildNumber": "20240101.1",
                "requestedFor": {"displayName": "Test User"},
                "sourceBranch": "refs/heads/main",
                "startTime": "2024-01-01T10:00:00Z",
                "finishTime": "2024-01-01T10:05:30Z",
            },
        }
        response = client.post("/webhook", json=payload)
        assert response.status_code == 200
        assert response.json()["status"] == "processed"

    def test_pr_created_event(self, client):
        payload = {
            "eventType": "git.pullrequest.created",
            "resource": {
                "title": "Fix login bug",
                "repository": {"name": "main-app"},
                "createdBy": {"displayName": "Dev User"},
                "sourceRefName": "refs/heads/fix/login",
                "targetRefName": "refs/heads/main",
                "reviewers": [{"displayName": "Reviewer 1"}],
                "status": "active",
            },
        }
        response = client.post("/webhook", json=payload)
        assert response.status_code == 200

    def test_invalid_payload(self, client):
        response = client.post("/webhook", content=b"not json", headers={"Content-Type": "application/json"})
        assert response.status_code == 400

    def test_unknown_event_type(self, client):
        payload = {
            "eventType": "custom.unknown.event",
            "resource": {"id": 1},
        }
        response = client.post("/webhook", json=payload)
        assert response.status_code == 200
        assert response.json()["event_type"] == "custom.unknown.event"


class TestEventsEndpoint:
    def test_get_events_empty(self, client):
        response = client.get("/events")
        assert response.status_code == 200
        assert "events" in response.json()

    def test_get_events_after_webhook(self, client):
        # Send a webhook event first
        payload = {
            "eventType": "build.complete",
            "resource": {
                "result": "failed",
                "definition": {"name": "test-pipeline"},
            },
        }
        client.post("/webhook", json=payload)

        response = client.get("/events")
        assert response.status_code == 200
        events = response.json()["events"]
        assert len(events) > 0

    def test_filter_events_by_type(self, client):
        # Send different event types
        client.post("/webhook", json={"eventType": "build.complete", "resource": {}})
        client.post("/webhook", json={"eventType": "git.push", "resource": {}})

        response = client.get("/events?event_type=build.complete")
        assert response.status_code == 200
