"""
Azure DevOps Dashboard

Generates HTML reports and terminal dashboards for pipeline health,
team velocity, and project metrics from Azure DevOps APIs.
"""

import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import click
import requests
from requests.auth import HTTPBasicAuth
from rich.console import Console
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

console = Console()


class DevOpsMetrics:
    """Collects and computes Azure DevOps project metrics."""

    def __init__(self, org_url: str, pat: str, project: str):
        self.org_url = org_url.rstrip("/")
        self.project = project
        self.auth = HTTPBasicAuth("", pat)
        self.session = requests.Session()
        self.session.auth = self.auth

    def _get(self, path: str) -> dict:
        url = f"{self.org_url}/{self.project}/_apis/{path}"
        resp = self.session.get(url, params={"api-version": "7.1"}, timeout=30)
        resp.raise_for_status()
        return resp.json()

    def get_pipeline_health(self, days: int = 7) -> dict:
        """Get pipeline success/failure rates."""
        min_time = (datetime.utcnow() - timedelta(days=days)).isoformat() + "Z"
        builds = self._get(f"build/builds?minTime={min_time}&$top=500")
        runs = builds.get("value", [])

        pipelines = defaultdict(lambda: {"total": 0, "succeeded": 0, "failed": 0, "durations": []})

        for run in runs:
            name = run.get("definition", {}).get("name", "Unknown")
            result = run.get("result", "")
            pipelines[name]["total"] += 1

            if result == "succeeded":
                pipelines[name]["succeeded"] += 1
            elif result == "failed":
                pipelines[name]["failed"] += 1

            start = run.get("startTime")
            finish = run.get("finishTime")
            if start and finish:
                try:
                    s = datetime.fromisoformat(start.replace("Z", "+00:00"))
                    f = datetime.fromisoformat(finish.replace("Z", "+00:00"))
                    pipelines[name]["durations"].append((f - s).total_seconds())
                except ValueError:
                    pass

        # Compute averages
        result = {}
        for name, data in pipelines.items():
            avg_dur = (
                sum(data["durations"]) / len(data["durations"])
                if data["durations"]
                else 0
            )
            success_rate = (
                data["succeeded"] / data["total"] * 100 if data["total"] > 0 else 0
            )
            result[name] = {
                "total_runs": data["total"],
                "succeeded": data["succeeded"],
                "failed": data["failed"],
                "success_rate": round(success_rate, 1),
                "avg_duration_sec": round(avg_dur),
            }

        return result

    def get_pr_metrics(self, days: int = 30) -> dict:
        """Get pull request metrics."""
        prs = self._get(
            f"git/repositories?api-version=7.1"
        )
        repos = prs.get("value", [])

        total_prs = 0
        merged = 0
        abandoned = 0
        active = 0
        review_times = []

        for repo in repos:
            repo_id = repo["id"]
            try:
                pr_list = self._get(
                    f"git/repositories/{repo_id}/pullrequests?searchCriteria.status=all&$top=100"
                )
            except requests.HTTPError:
                continue

            for pr in pr_list.get("value", []):
                created = pr.get("creationDate", "")
                try:
                    created_dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
                    if created_dt < datetime.now(created_dt.tzinfo) - timedelta(days=days):
                        continue
                except (ValueError, TypeError):
                    continue

                total_prs += 1
                status = pr.get("status", "")
                if status == "completed":
                    merged += 1
                    closed = pr.get("closedDate")
                    if closed:
                        try:
                            closed_dt = datetime.fromisoformat(closed.replace("Z", "+00:00"))
                            review_hours = (closed_dt - created_dt).total_seconds() / 3600
                            review_times.append(review_hours)
                        except ValueError:
                            pass
                elif status == "abandoned":
                    abandoned += 1
                elif status == "active":
                    active += 1

        avg_review = sum(review_times) / len(review_times) if review_times else 0

        return {
            "total": total_prs,
            "merged": merged,
            "abandoned": abandoned,
            "active": active,
            "avg_review_hours": round(avg_review, 1),
            "merge_rate": round(merged / total_prs * 100, 1) if total_prs > 0 else 0,
        }

    def get_work_item_stats(self) -> dict:
        """Get work item statistics using WIQL."""
        wiql = {
            "query": (
                "SELECT [System.Id], [System.State], [System.WorkItemType] "
                "FROM workitems "
                "WHERE [System.TeamProject] = @project "
                "AND [System.State] <> 'Removed' "
                "ORDER BY [System.ChangedDate] DESC"
            )
        }

        url = f"{self.org_url}/{self.project}/_apis/wit/wiql"
        resp = self.session.post(
            url, json=wiql, params={"api-version": "7.1", "$top": 200}, timeout=30
        )
        resp.raise_for_status()
        work_items = resp.json().get("workItems", [])

        if not work_items:
            return {"total": 0, "by_state": {}, "by_type": {}}

        # Batch fetch work item details
        ids = [str(wi["id"]) for wi in work_items[:200]]
        details_url = f"{self.org_url}/{self.project}/_apis/wit/workitems"
        resp = self.session.get(
            details_url,
            params={
                "ids": ",".join(ids),
                "fields": "System.State,System.WorkItemType",
                "api-version": "7.1",
            },
            timeout=30,
        )
        resp.raise_for_status()
        items = resp.json().get("value", [])

        by_state = defaultdict(int)
        by_type = defaultdict(int)
        for item in items:
            fields = item.get("fields", {})
            by_state[fields.get("System.State", "Unknown")] += 1
            by_type[fields.get("System.WorkItemType", "Unknown")] += 1

        return {
            "total": len(items),
            "by_state": dict(by_state),
            "by_type": dict(by_type),
        }


def render_pipeline_table(health: dict) -> Table:
    """Render pipeline health as a rich table."""
    table = Table(title="Pipeline Health", show_header=True, header_style="bold cyan")
    table.add_column("Pipeline", width=30)
    table.add_column("Runs", justify="right", width=6)
    table.add_column("Pass", justify="right", width=6, style="green")
    table.add_column("Fail", justify="right", width=6, style="red")
    table.add_column("Rate", justify="right", width=8)
    table.add_column("Avg Time", justify="right", width=10)

    for name, data in sorted(health.items(), key=lambda x: x[1]["success_rate"]):
        rate = data["success_rate"]
        rate_style = "green" if rate >= 90 else "yellow" if rate >= 70 else "red"
        minutes, seconds = divmod(data["avg_duration_sec"], 60)
        duration = f"{minutes}m {seconds}s"

        table.add_row(
            name[:30],
            str(data["total_runs"]),
            str(data["succeeded"]),
            str(data["failed"]),
            f"[{rate_style}]{rate}%[/{rate_style}]",
            duration,
        )

    return table


def render_pr_panel(pr_metrics: dict) -> Panel:
    """Render PR metrics as a panel."""
    text = Text()
    text.append(f"Total PRs:        {pr_metrics['total']}\n")
    text.append(f"Merged:           {pr_metrics['merged']}\n", style="green")
    text.append(f"Active:           {pr_metrics['active']}\n", style="yellow")
    text.append(f"Abandoned:        {pr_metrics['abandoned']}\n", style="red")
    text.append(f"Merge Rate:       {pr_metrics['merge_rate']}%\n")
    text.append(f"Avg Review Time:  {pr_metrics['avg_review_hours']}h\n")
    return Panel(text, title="Pull Requests (30d)", border_style="blue")


def render_workitem_panel(wi_stats: dict) -> Panel:
    """Render work item stats as a panel."""
    text = Text()
    text.append(f"Total Items: {wi_stats['total']}\n\n")

    text.append("By State:\n", style="bold")
    for state, count in sorted(wi_stats.get("by_state", {}).items()):
        text.append(f"  {state}: {count}\n")

    text.append("\nBy Type:\n", style="bold")
    for wtype, count in sorted(wi_stats.get("by_type", {}).items()):
        text.append(f"  {wtype}: {count}\n")

    return Panel(text, title="Work Items", border_style="green")


def generate_html_report(health: dict, pr_metrics: dict, wi_stats: dict, output_path: str) -> None:
    """Generate an HTML dashboard report."""
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Azure DevOps Dashboard</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #1a1a2e; color: #eee; padding: 20px; }}
        .header {{ text-align: center; padding: 20px; margin-bottom: 30px; }}
        .header h1 {{ color: #0078d4; font-size: 28px; }}
        .header .timestamp {{ color: #888; font-size: 14px; margin-top: 5px; }}
        .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 20px; }}
        .card {{ background: #16213e; border-radius: 8px; padding: 20px; border: 1px solid #0f3460; }}
        .card h2 {{ color: #0078d4; margin-bottom: 15px; font-size: 18px; }}
        table {{ width: 100%; border-collapse: collapse; }}
        th, td {{ padding: 8px 12px; text-align: left; border-bottom: 1px solid #0f3460; }}
        th {{ color: #0078d4; font-weight: 600; }}
        .stat {{ display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #0f3460; }}
        .stat-label {{ color: #888; }}
        .stat-value {{ font-weight: bold; }}
        .good {{ color: #4caf50; }}
        .warn {{ color: #ff9800; }}
        .bad {{ color: #f44336; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>Azure DevOps Dashboard</h1>
        <div class="timestamp">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>
    </div>
    <div class="grid">
        <div class="card">
            <h2>Pipeline Health (7 days)</h2>
            <table>
                <tr><th>Pipeline</th><th>Runs</th><th>Rate</th><th>Avg Time</th></tr>
"""

    for name, data in sorted(health.items(), key=lambda x: x[1]["success_rate"]):
        rate = data["success_rate"]
        rate_class = "good" if rate >= 90 else "warn" if rate >= 70 else "bad"
        m, s = divmod(data["avg_duration_sec"], 60)
        html += f'                <tr><td>{name}</td><td>{data["total_runs"]}</td><td class="{rate_class}">{rate}%</td><td>{m}m {s}s</td></tr>\n'

    html += f"""            </table>
        </div>
        <div class="card">
            <h2>Pull Requests (30 days)</h2>
            <div class="stat"><span class="stat-label">Total</span><span class="stat-value">{pr_metrics["total"]}</span></div>
            <div class="stat"><span class="stat-label">Merged</span><span class="stat-value good">{pr_metrics["merged"]}</span></div>
            <div class="stat"><span class="stat-label">Active</span><span class="stat-value warn">{pr_metrics["active"]}</span></div>
            <div class="stat"><span class="stat-label">Abandoned</span><span class="stat-value bad">{pr_metrics["abandoned"]}</span></div>
            <div class="stat"><span class="stat-label">Merge Rate</span><span class="stat-value">{pr_metrics["merge_rate"]}%</span></div>
            <div class="stat"><span class="stat-label">Avg Review Time</span><span class="stat-value">{pr_metrics["avg_review_hours"]}h</span></div>
        </div>
        <div class="card">
            <h2>Work Items</h2>
            <div class="stat"><span class="stat-label">Total</span><span class="stat-value">{wi_stats["total"]}</span></div>
"""

    for state, count in sorted(wi_stats.get("by_state", {}).items()):
        html += f'            <div class="stat"><span class="stat-label">{state}</span><span class="stat-value">{count}</span></div>\n'

    html += """        </div>
    </div>
</body>
</html>"""

    Path(output_path).write_text(html)
    console.print(f"[green]HTML report saved to {output_path}[/green]")


@click.group()
def cli():
    """Azure DevOps project dashboard and reporting."""
    pass


@cli.command()
@click.option("--org", envvar="AZDO_ORG_URL", required=True)
@click.option("--pat", envvar="AZDO_PAT", required=True)
@click.option("--project", envvar="AZDO_PROJECT", required=True)
@click.option("--days", default=7, help="Days to analyze for pipeline health")
def terminal(org: str, pat: str, project: str, days: int):
    """Show terminal dashboard."""
    metrics = DevOpsMetrics(org, pat, project)

    console.print(f"\n[bold cyan]Azure DevOps Dashboard: {project}[/bold cyan]\n")

    with console.status("Fetching pipeline health..."):
        health = metrics.get_pipeline_health(days)
    console.print(render_pipeline_table(health))

    with console.status("Fetching PR metrics..."):
        pr_metrics = metrics.get_pr_metrics()
    console.print(render_pr_panel(pr_metrics))

    with console.status("Fetching work item stats..."):
        wi_stats = metrics.get_work_item_stats()
    console.print(render_workitem_panel(wi_stats))


@cli.command()
@click.option("--org", envvar="AZDO_ORG_URL", required=True)
@click.option("--pat", envvar="AZDO_PAT", required=True)
@click.option("--project", envvar="AZDO_PROJECT", required=True)
@click.option("--output", default="dashboard.html", help="Output HTML file path")
@click.option("--days", default=7)
def html(org: str, pat: str, project: str, output: str, days: int):
    """Generate HTML dashboard report."""
    metrics = DevOpsMetrics(org, pat, project)

    with console.status("Collecting metrics..."):
        health = metrics.get_pipeline_health(days)
        pr_metrics = metrics.get_pr_metrics()
        wi_stats = metrics.get_work_item_stats()

    generate_html_report(health, pr_metrics, wi_stats, output)


@cli.command()
@click.option("--org", envvar="AZDO_ORG_URL", required=True)
@click.option("--pat", envvar="AZDO_PAT", required=True)
@click.option("--project", envvar="AZDO_PROJECT", required=True)
@click.option("--days", default=7)
def json_export(org: str, pat: str, project: str, days: int):
    """Export metrics as JSON."""
    metrics = DevOpsMetrics(org, pat, project)

    data = {
        "generated_at": datetime.now().isoformat(),
        "project": project,
        "pipeline_health": metrics.get_pipeline_health(days),
        "pr_metrics": metrics.get_pr_metrics(),
        "work_items": metrics.get_work_item_stats(),
    }

    print(json.dumps(data, indent=2, default=str))


if __name__ == "__main__":
    cli()
