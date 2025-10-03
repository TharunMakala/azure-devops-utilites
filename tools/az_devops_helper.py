#!/usr/bin/env python3
"""
az_devops_helper.py — Azure DevOps CLI utility tool.

Provides quick access to common ADO operations via the Azure DevOps Python SDK.

Usage:
    python az_devops_helper.py --help
    python az_devops_helper.py projects  --org myorg --pat $ADO_PAT
    python az_devops_helper.py runs      --org myorg --project MyProject --pat $ADO_PAT
    python az_devops_helper.py workitems --org myorg --project MyProject --pat $ADO_PAT
"""

import csv
import os
import sys
from datetime import datetime, timezone

import click
from azure.devops.connection import Connection
from azure.devops.v7_1.build.models import BuildQueryOrder
from msrest.authentication import BasicAuthentication
from rich.console import Console
from rich.table import Table

console = Console()


# ── Helpers ───────────────────────────────────────────────────────────────────

def get_connection(org: str, pat: str) -> Connection:
    """Create an authenticated Azure DevOps connection."""
    org_url = f"https://dev.azure.com/{org}" if not org.startswith("http") else org
    credentials = BasicAuthentication("", pat)
    return Connection(base_url=org_url, creds=credentials)


def resolve_pat(pat: str | None) -> str:
    """Resolve PAT from argument or ADO_PAT environment variable."""
    token = pat or os.getenv("ADO_PAT")
    if not token:
        console.print("[red]Error:[/red] PAT required. Pass --pat or set ADO_PAT env var.")
        sys.exit(1)
    return token


def format_date(dt) -> str:
    """Format a datetime object for display."""
    if dt is None:
        return "—"
    if isinstance(dt, str):
        return dt[:19].replace("T", " ")
    return dt.strftime("%Y-%m-%d %H:%M")


# ── CLI root ──────────────────────────────────────────────────────────────────

@click.group()
@click.version_option("1.0.0")
def cli():
    """Azure DevOps Helper — common ADO operations from the command line."""


# ── projects ──────────────────────────────────────────────────────────────────

@cli.command()
@click.option("--org",   required=True, help="Azure DevOps organization name.")
@click.option("--pat",   default=None,  help="Personal Access Token (or set ADO_PAT).")
@click.option("--json",  "as_json", is_flag=True, help="Output as JSON.")
def projects(org: str, pat: str, as_json: bool):
    """List all projects in the organization."""
    conn = get_connection(org, resolve_pat(pat))
    client = conn.clients.get_core_client()

    with console.status("Fetching projects..."):
        result = client.get_projects()

    if as_json:
        import json
        data = [{"id": p.id, "name": p.name, "state": p.state, "visibility": p.visibility}
                for p in result]
        click.echo(json.dumps(data, indent=2))
        return

    table = Table(title=f"Projects in '{org}'", show_lines=False)
    table.add_column("Name",        style="cyan", no_wrap=True)
    table.add_column("State",       style="green")
    table.add_column("Visibility",  style="yellow")
    table.add_column("ID",          style="dim")

    for p in sorted(result, key=lambda x: x.name):
        table.add_row(p.name, p.state or "—", p.visibility or "—", p.id)

    console.print(table)
    console.print(f"\n[bold]{len(result)}[/bold] project(s) found.")


# ── runs ──────────────────────────────────────────────────────────────────────

@cli.command()
@click.option("--org",     required=True,  help="Azure DevOps organization name.")
@click.option("--project", required=True,  help="Project name.")
@click.option("--pat",     default=None,   help="Personal Access Token (or set ADO_PAT).")
@click.option("--limit",   default=10,     show_default=True, help="Number of runs to show.")
@click.option("--pipeline", default=None,  help="Filter by pipeline name (partial match).")
def runs(org: str, project: str, pat: str, limit: int, pipeline: str | None):
    """List recent pipeline runs."""
    conn = get_connection(org, resolve_pat(pat))
    client = conn.clients.get_build_client()

    with console.status("Fetching pipeline runs..."):
        builds = client.get_builds(
            project=project,
            top=limit * 3,   # Fetch more to allow for name filtering
            query_order=BuildQueryOrder.QUEUE_TIME_DESCENDING,
        )

    if pipeline:
        builds = [b for b in builds if pipeline.lower() in (b.definition.name or "").lower()]

    builds = builds[:limit]

    table = Table(title=f"Recent runs — {project}", show_lines=False)
    table.add_column("ID",         style="dim",    no_wrap=True)
    table.add_column("Pipeline",   style="cyan",   no_wrap=True)
    table.add_column("Branch",     style="yellow", no_wrap=True)
    table.add_column("Status",     no_wrap=True)
    table.add_column("Result",     no_wrap=True)
    table.add_column("Queued",     style="dim",    no_wrap=True)
    table.add_column("Requested By", style="dim")

    STATUS_STYLE = {"completed": "green", "inProgress": "blue", "notStarted": "yellow"}
    RESULT_STYLE = {"succeeded": "green", "failed": "red", "canceled": "yellow", "partiallySucceeded": "yellow"}

    for b in builds:
        status = b.status or "—"
        result = b.result or "—"
        table.add_row(
            str(b.id),
            b.definition.name if b.definition else "—",
            (b.source_branch or "").replace("refs/heads/", ""),
            f"[{STATUS_STYLE.get(status, 'white')}]{status}[/]",
            f"[{RESULT_STYLE.get(result, 'white')}]{result}[/]",
            format_date(b.queue_time),
            b.requested_by.display_name if b.requested_by else "—",
        )

    console.print(table)


# ── workitems ─────────────────────────────────────────────────────────────────

@cli.command()
@click.option("--org",     required=True, help="Azure DevOps organization name.")
@click.option("--project", required=True, help="Project name.")
@click.option("--pat",     default=None,  help="Personal Access Token (or set ADO_PAT).")
@click.option("--query",   default="SELECT [Id],[Title],[State],[AssignedTo] FROM WorkItems WHERE [System.TeamProject] = @project AND [State] <> 'Closed' ORDER BY [Id] DESC",
              help="WIQL query string.")
@click.option("--output",  default=None,  help="Export results to a CSV file.")
def workitems(org: str, project: str, pat: str, query: str, output: str | None):
    """Query and display work items."""
    conn = get_connection(org, resolve_pat(pat))
    wit_client = conn.clients.get_work_item_tracking_client()

    with console.status("Running work item query..."):
        from azure.devops.v7_1.work_item_tracking.models import Wiql
        wiql = Wiql(query=query)
        result = wit_client.query_by_wiql(wiql, project=project, top=200)

    if not result.work_items:
        console.print("[yellow]No work items matched the query.[/yellow]")
        return

    ids = [wi.id for wi in result.work_items]
    fields = ["System.Id", "System.Title", "System.State", "System.AssignedTo", "System.WorkItemType"]

    with console.status(f"Fetching {len(ids)} work item(s)..."):
        items = wit_client.get_work_items(ids=ids, fields=fields)

    rows = []
    for item in items:
        f = item.fields
        assigned = f.get("System.AssignedTo", {})
        rows.append({
            "ID":         str(f.get("System.Id", "")),
            "Type":       f.get("System.WorkItemType", ""),
            "State":      f.get("System.State", ""),
            "Title":      f.get("System.Title", ""),
            "Assigned To": assigned.get("displayName", "Unassigned") if isinstance(assigned, dict) else str(assigned or "Unassigned"),
        })

    if output:
        with open(output, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=rows[0].keys())
            writer.writeheader()
            writer.writerows(rows)
        console.print(f"[green]Exported {len(rows)} item(s) to {output}[/green]")
        return

    table = Table(title=f"Work Items — {project}", show_lines=False)
    table.add_column("ID",          style="dim",    no_wrap=True)
    table.add_column("Type",        style="yellow", no_wrap=True)
    table.add_column("State",       style="cyan",   no_wrap=True)
    table.add_column("Assigned To", style="dim")
    table.add_column("Title")

    for row in rows:
        table.add_row(row["ID"], row["Type"], row["State"], row["Assigned To"], row["Title"])

    console.print(table)
    console.print(f"\n[bold]{len(rows)}[/bold] item(s) found.")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    cli()
