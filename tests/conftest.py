"""Shared pytest fixtures for Azure DevOps utilities tests."""

import json
import os
from unittest.mock import MagicMock, patch

import pytest


@pytest.fixture
def mock_env_vars(monkeypatch):
    """Set required environment variables for testing."""
    monkeypatch.setenv("AZDO_ORG_URL", "https://dev.azure.com/testorg")
    monkeypatch.setenv("AZDO_PAT", "test-pat-token")
    monkeypatch.setenv("AZDO_PROJECT", "TestProject")


@pytest.fixture
def sample_build_response():
    """Sample Azure DevOps build API response."""
    return {
        "count": 2,
        "value": [
            {
                "id": 101,
                "buildNumber": "20240101.1",
                "status": "completed",
                "result": "succeeded",
                "definition": {"id": 1, "name": "CI-Pipeline"},
                "sourceBranch": "refs/heads/main",
                "sourceVersion": "abc123",
                "requestedFor": {"displayName": "Test User"},
                "startTime": "2024-01-01T10:00:00Z",
                "finishTime": "2024-01-01T10:05:30Z",
                "url": "https://dev.azure.com/testorg/TestProject/_build/results?buildId=101",
            },
            {
                "id": 102,
                "buildNumber": "20240101.2",
                "status": "completed",
                "result": "failed",
                "definition": {"id": 2, "name": "CD-Pipeline"},
                "sourceBranch": "refs/heads/feature/test",
                "sourceVersion": "def456",
                "requestedFor": {"displayName": "Another User"},
                "startTime": "2024-01-01T11:00:00Z",
                "finishTime": "2024-01-01T11:12:45Z",
                "url": "https://dev.azure.com/testorg/TestProject/_build/results?buildId=102",
            },
        ],
    }


@pytest.fixture
def sample_repositories_response():
    """Sample Azure DevOps repositories API response."""
    return {
        "count": 2,
        "value": [
            {
                "id": "repo-1",
                "name": "main-app",
                "defaultBranch": "refs/heads/main",
                "size": 1024000,
                "remoteUrl": "https://dev.azure.com/testorg/TestProject/_git/main-app",
            },
            {
                "id": "repo-2",
                "name": "shared-lib",
                "defaultBranch": "refs/heads/main",
                "size": 512000,
                "remoteUrl": "https://dev.azure.com/testorg/TestProject/_git/shared-lib",
            },
        ],
    }


@pytest.fixture
def sample_variable_groups_response():
    """Sample variable groups API response."""
    return {
        "count": 2,
        "value": [
            {
                "id": 1,
                "name": "app-settings-dev",
                "variables": {
                    "APP_ENV": {"value": "dev", "isSecret": False},
                    "DB_HOST": {"value": "dev-db.internal", "isSecret": False},
                    "DB_PASSWORD": {"value": "plaintext-bad", "isSecret": False},
                },
            },
            {
                "id": 2,
                "name": "app-settings-prod",
                "variables": {
                    "APP_ENV": {"value": "production", "isSecret": False},
                    "DB_HOST": {"value": "prod-db.internal", "isSecret": False},
                    "DB_PASSWORD": {"isSecret": True},
                },
                "providerData": {"serviceEndpointId": "kv-endpoint-id"},
            },
        ],
    }


@pytest.fixture
def tmp_config_dir(tmp_path):
    """Create temporary config directory with sample configs."""
    import yaml

    configs = {
        "dev": {
            "app": {"name": "test-app", "version": "1.0.0", "debug": True},
            "logging": {"level": "debug"},
            "database": {"host": "dev-db", "name": "devops_db", "ssl": False},
        },
        "staging": {
            "app": {"name": "test-app", "version": "1.0.0", "debug": False},
            "logging": {"level": "info"},
            "database": {"host": "staging-db", "name": "devops_db", "ssl": True},
        },
        "production": {
            "app": {"name": "test-app", "version": "1.0.0", "debug": False},
            "logging": {"level": "warning"},
            "database": {"host": "prod-db", "name": "devops_db", "ssl": True},
        },
    }

    for env, config in configs.items():
        env_dir = tmp_path / env
        env_dir.mkdir()
        with open(env_dir / "config.yaml", "w") as f:
            yaml.dump(config, f)

    return tmp_path
