"""Unit tests for the compliance checker."""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools" / "compliance-checker"))

from checker import (
    CheckResult,
    ComplianceReport,
    Severity,
    Status,
    check_variable_groups,
)


class TestComplianceReport:
    def test_empty_report(self):
        report = ComplianceReport(project="test", organization="org")
        assert report.passed == 0
        assert report.failed == 0
        assert report.warnings == 0

    def test_report_counts(self):
        report = ComplianceReport(project="test", organization="org")
        report.results = [
            CheckResult("T-1", "test1", "desc", Severity.HIGH, Status.PASS),
            CheckResult("T-2", "test2", "desc", Severity.HIGH, Status.FAIL),
            CheckResult("T-3", "test3", "desc", Severity.MEDIUM, Status.WARN),
            CheckResult("T-4", "test4", "desc", Severity.CRITICAL, Status.FAIL),
        ]
        assert report.passed == 1
        assert report.failed == 2
        assert report.warnings == 1
        assert report.critical_failures == 1

    def test_no_critical_failures(self):
        report = ComplianceReport(project="test", organization="org")
        report.results = [
            CheckResult("T-1", "test1", "desc", Severity.HIGH, Status.FAIL),
        ]
        assert report.critical_failures == 0


class TestVariableGroupChecks:
    def test_detects_plaintext_secret(self, sample_variable_groups_response):
        client = MagicMock()
        client.get_variable_groups.return_value = sample_variable_groups_response["value"]

        results = check_variable_groups(client)

        critical_fails = [
            r for r in results
            if r.severity == Severity.CRITICAL and r.status == Status.FAIL
        ]
        assert len(critical_fails) > 0
        assert any("DB_PASSWORD" in r.name for r in critical_fails)

    def test_passes_for_proper_secrets(self):
        client = MagicMock()
        client.get_variable_groups.return_value = [
            {
                "name": "secure-group",
                "variables": {
                    "APP_ENV": {"value": "prod", "isSecret": False},
                    "DB_PASSWORD": {"isSecret": True},
                },
                "providerData": {"serviceEndpointId": "kv-id"},
            }
        ]

        results = check_variable_groups(client)
        critical_fails = [
            r for r in results
            if r.severity == Severity.CRITICAL and r.status == Status.FAIL
        ]
        assert len(critical_fails) == 0
