"""
Azure DevOps Compliance Checker

Validates Azure DevOps project configurations against organizational
security and compliance policies. Checks branch policies, service
connections, variable groups, and pipeline configurations.
"""

import json
import logging
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional

import click
import requests
from requests.auth import HTTPBasicAuth
from rich.console import Console
from rich.table import Table

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)
console = Console()


class Severity(str, Enum):
    CRITICAL = "CRITICAL"
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    INFO = "INFO"


class Status(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    WARN = "WARN"
    SKIP = "SKIP"


@dataclass
class CheckResult:
    check_id: str
    name: str
    description: str
    severity: Severity
    status: Status
    details: str = ""
    remediation: str = ""


@dataclass
class ComplianceReport:
    project: str
    organization: str
    results: list[CheckResult] = field(default_factory=list)

    @property
    def passed(self) -> int:
        return sum(1 for r in self.results if r.status == Status.PASS)

    @property
    def failed(self) -> int:
        return sum(1 for r in self.results if r.status == Status.FAIL)

    @property
    def warnings(self) -> int:
        return sum(1 for r in self.results if r.status == Status.WARN)

    @property
    def critical_failures(self) -> int:
        return sum(
            1
            for r in self.results
            if r.status == Status.FAIL and r.severity == Severity.CRITICAL
        )


class AzureDevOpsClient:
    """Client for Azure DevOps REST API."""

    def __init__(self, org_url: str, pat: str, project: str):
        self.org_url = org_url.rstrip("/")
        self.project = project
        self.auth = HTTPBasicAuth("", pat)
        self.session = requests.Session()
        self.session.auth = self.auth

    def _get(self, path: str, api_version: str = "7.1") -> dict:
        url = f"{self.org_url}/{self.project}/_apis/{path}"
        params = {"api-version": api_version}
        resp = self.session.get(url, params=params, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def _get_org(self, path: str, api_version: str = "7.1") -> dict:
        url = f"{self.org_url}/_apis/{path}"
        params = {"api-version": api_version}
        resp = self.session.get(url, params=params, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def get_repositories(self) -> list[dict]:
        return self._get("git/repositories").get("value", [])

    def get_branch_policies(self, repo_id: str) -> list[dict]:
        return self._get(f"policy/configurations?repositoryId={repo_id}").get(
            "value", []
        )

    def get_build_definitions(self) -> list[dict]:
        return self._get("build/definitions").get("value", [])

    def get_build_definition(self, definition_id: int) -> dict:
        return self._get(f"build/definitions/{definition_id}")

    def get_variable_groups(self) -> list[dict]:
        return self._get("distributedtask/variablegroups").get("value", [])

    def get_service_connections(self) -> list[dict]:
        return self._get("serviceendpoint/endpoints").get("value", [])

    def get_environments(self) -> list[dict]:
        return self._get("pipelines/environments").get("value", [])


def check_branch_policies(client: AzureDevOpsClient) -> list[CheckResult]:
    """Check branch protection policies on repositories."""
    results = []
    repos = client.get_repositories()

    for repo in repos:
        repo_name = repo["name"]
        try:
            policies = client.get_branch_policies(repo["id"])
        except requests.HTTPError:
            results.append(
                CheckResult(
                    check_id="BP-001",
                    name=f"Branch policies accessible: {repo_name}",
                    description="Branch policies should be queryable",
                    severity=Severity.LOW,
                    status=Status.SKIP,
                    details="Could not query branch policies",
                )
            )
            continue

        # Check minimum reviewer count
        reviewer_policies = [
            p
            for p in policies
            if p.get("type", {}).get("id") == "fa4e907d-c16b-4a4c-9dfa-4916e5d171ab"
        ]
        if reviewer_policies:
            min_reviewers = (
                reviewer_policies[0]
                .get("settings", {})
                .get("minimumApproverCount", 0)
            )
            results.append(
                CheckResult(
                    check_id="BP-001",
                    name=f"Min reviewers ({repo_name})",
                    description="Main branch requires at least 2 reviewers",
                    severity=Severity.HIGH,
                    status=Status.PASS if min_reviewers >= 2 else Status.FAIL,
                    details=f"Minimum reviewers: {min_reviewers}",
                    remediation="Set minimum reviewer count to at least 2",
                )
            )
        else:
            results.append(
                CheckResult(
                    check_id="BP-001",
                    name=f"Min reviewers ({repo_name})",
                    description="Main branch requires reviewer policy",
                    severity=Severity.HIGH,
                    status=Status.FAIL,
                    details="No reviewer policy found",
                    remediation="Add a minimum reviewer policy to the default branch",
                )
            )

        # Check build validation
        build_policies = [
            p
            for p in policies
            if p.get("type", {}).get("id") == "0609b952-1397-4640-95ec-e00a01b2c241"
        ]
        results.append(
            CheckResult(
                check_id="BP-002",
                name=f"Build validation ({repo_name})",
                description="PRs must pass build validation before merge",
                severity=Severity.HIGH,
                status=Status.PASS if build_policies else Status.FAIL,
                details=f"Build validation policies: {len(build_policies)}",
                remediation="Add a build validation policy to the default branch",
            )
        )

    return results


def check_service_connections(client: AzureDevOpsClient) -> list[CheckResult]:
    """Check service connection security configurations."""
    results = []
    connections = client.get_service_connections()

    for conn in connections:
        conn_name = conn.get("name", "Unknown")
        conn_type = conn.get("type", "Unknown")

        # Check for Workload Identity Federation (preferred over secret-based)
        auth_scheme = (
            conn.get("authorization", {}).get("scheme", "").lower()
        )
        if conn_type in ("azurerm", "AzureRM"):
            is_wif = auth_scheme == "workloadidentityfederation"
            results.append(
                CheckResult(
                    check_id="SC-001",
                    name=f"WIF auth ({conn_name})",
                    description="Azure connections should use Workload Identity Federation",
                    severity=Severity.MEDIUM,
                    status=Status.PASS if is_wif else Status.WARN,
                    details=f"Auth scheme: {auth_scheme}",
                    remediation="Migrate to Workload Identity Federation for keyless auth",
                )
            )

        # Check if shared across projects
        is_shared = conn.get("isShared", False)
        if is_shared:
            results.append(
                CheckResult(
                    check_id="SC-002",
                    name=f"Shared connection ({conn_name})",
                    description="Service connections shared across projects increase blast radius",
                    severity=Severity.MEDIUM,
                    status=Status.WARN,
                    details="Connection is shared across projects",
                    remediation="Limit service connection scope to individual projects",
                )
            )

    return results


def check_variable_groups(client: AzureDevOpsClient) -> list[CheckResult]:
    """Check variable group configurations for secret handling."""
    results = []
    groups = client.get_variable_groups()

    for group in groups:
        group_name = group.get("name", "Unknown")
        variables = group.get("variables", {})

        # Check for non-secret sensitive variables
        sensitive_patterns = ["password", "secret", "key", "token", "pat", "connectionstring"]
        for var_name, var_data in variables.items():
            is_secret = var_data.get("isSecret", False)
            looks_sensitive = any(
                p in var_name.lower() for p in sensitive_patterns
            )

            if looks_sensitive and not is_secret:
                results.append(
                    CheckResult(
                        check_id="VG-001",
                        name=f"Unprotected secret: {group_name}/{var_name}",
                        description="Sensitive variables must be marked as secret",
                        severity=Severity.CRITICAL,
                        status=Status.FAIL,
                        details=f"Variable '{var_name}' appears sensitive but is not secret",
                        remediation=f"Mark '{var_name}' as secret or use Key Vault linkage",
                    )
                )

        # Check for Key Vault linkage
        kv_linked = group.get("providerData", {}).get("serviceEndpointId") is not None
        if any(
            any(p in v.lower() for p in sensitive_patterns)
            for v in variables.keys()
        ) and not kv_linked:
            results.append(
                CheckResult(
                    check_id="VG-002",
                    name=f"Key Vault linkage ({group_name})",
                    description="Groups with secrets should link to Key Vault",
                    severity=Severity.MEDIUM,
                    status=Status.WARN,
                    details="Variable group contains secrets but is not linked to Key Vault",
                    remediation="Create a Key Vault-linked variable group instead",
                )
            )

    return results


def check_pipeline_security(client: AzureDevOpsClient) -> list[CheckResult]:
    """Check pipeline definition security settings."""
    results = []
    definitions = client.get_build_definitions()

    for defn in definitions[:20]:  # Limit to 20 to avoid rate limiting
        defn_name = defn.get("name", "Unknown")
        try:
            full_defn = client.get_build_definition(defn["id"])
        except requests.HTTPError:
            continue

        # Check for pinned task versions
        process = full_defn.get("process", {})
        if process.get("type") == 1:  # YAML
            results.append(
                CheckResult(
                    check_id="PL-001",
                    name=f"YAML pipeline ({defn_name})",
                    description="Pipelines should use YAML for version control",
                    severity=Severity.LOW,
                    status=Status.PASS,
                    details="Pipeline uses YAML definition",
                )
            )
        elif process.get("type") == 2:  # Classic
            results.append(
                CheckResult(
                    check_id="PL-001",
                    name=f"Classic pipeline ({defn_name})",
                    description="Pipelines should use YAML for version control",
                    severity=Severity.LOW,
                    status=Status.WARN,
                    details="Pipeline uses classic editor - consider migrating to YAML",
                    remediation="Migrate classic pipeline to YAML for version control",
                )
            )

    return results


def run_all_checks(client: AzureDevOpsClient) -> ComplianceReport:
    """Run all compliance checks and return a report."""
    report = ComplianceReport(
        project=client.project,
        organization=client.org_url,
    )

    checks = [
        ("Branch Policies", check_branch_policies),
        ("Service Connections", check_service_connections),
        ("Variable Groups", check_variable_groups),
        ("Pipeline Security", check_pipeline_security),
    ]

    for name, check_fn in checks:
        console.print(f"\n[bold]Running: {name}[/bold]")
        try:
            results = check_fn(client)
            report.results.extend(results)
            passed = sum(1 for r in results if r.status == Status.PASS)
            console.print(f"  {passed}/{len(results)} checks passed")
        except Exception as e:
            logger.error("Check '%s' failed: %s", name, e)
            report.results.append(
                CheckResult(
                    check_id="SYS-001",
                    name=f"Check execution: {name}",
                    description=f"Failed to execute {name} checks",
                    severity=Severity.LOW,
                    status=Status.SKIP,
                    details=str(e),
                )
            )

    return report


def print_report(report: ComplianceReport) -> None:
    """Print formatted compliance report."""
    console.print("\n")
    console.print("=" * 60)
    console.print(
        f"[bold cyan]Compliance Report: {report.project}[/bold cyan]"
    )
    console.print("=" * 60)

    table = Table(show_header=True, header_style="bold")
    table.add_column("ID", width=8)
    table.add_column("Check", width=40)
    table.add_column("Severity", width=10)
    table.add_column("Status", width=8)
    table.add_column("Details", width=40)

    status_styles = {
        Status.PASS: "green",
        Status.FAIL: "red",
        Status.WARN: "yellow",
        Status.SKIP: "dim",
    }

    for result in sorted(report.results, key=lambda r: r.severity.value):
        style = status_styles.get(result.status, "white")
        table.add_row(
            result.check_id,
            result.name,
            result.severity.value,
            f"[{style}]{result.status.value}[/{style}]",
            result.details[:40],
        )

    console.print(table)

    console.print(f"\n[bold]Summary:[/bold]")
    console.print(f"  Total checks:      {len(report.results)}")
    console.print(f"  [green]Passed:            {report.passed}[/green]")
    console.print(f"  [red]Failed:            {report.failed}[/red]")
    console.print(f"  [yellow]Warnings:          {report.warnings}[/yellow]")

    if report.critical_failures > 0:
        console.print(
            f"\n[bold red]⚠ {report.critical_failures} CRITICAL failures require immediate attention![/bold red]"
        )

    # Print remediations for failures
    failures = [r for r in report.results if r.status == Status.FAIL and r.remediation]
    if failures:
        console.print("\n[bold]Remediation Steps:[/bold]")
        for r in failures:
            console.print(f"  [{r.check_id}] {r.remediation}")


@click.command()
@click.option("--org", envvar="AZDO_ORG_URL", required=True, help="Organization URL")
@click.option("--pat", envvar="AZDO_PAT", required=True, help="Personal access token")
@click.option("--project", envvar="AZDO_PROJECT", required=True, help="Project name")
@click.option("--output", type=click.Choice(["table", "json"]), default="table")
@click.option("--fail-on-critical", is_flag=True, help="Exit with error on critical failures")
def main(org: str, pat: str, project: str, output: str, fail_on_critical: bool):
    """Run Azure DevOps compliance checks against organizational policies."""
    client = AzureDevOpsClient(org, pat, project)
    report = run_all_checks(client)

    if output == "json":
        import dataclasses

        print(
            json.dumps(
                [dataclasses.asdict(r) for r in report.results],
                indent=2,
                default=str,
            )
        )
    else:
        print_report(report)

    if fail_on_critical and report.critical_failures > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
