"""
Multi-Environment Configuration Manager

Manages and validates configuration across Azure DevOps environments.
Supports config drift detection, secret rotation tracking, and
environment promotion workflows.
"""

import hashlib
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional

import click
import yaml
from rich.console import Console
from rich.table import Table
from rich.tree import Tree

console = Console()


class ConfigStore:
    """Manages configuration files across environments."""

    def __init__(self, config_dir: str = "config"):
        self.config_dir = Path(config_dir)
        self.environments = ["dev", "staging", "production"]

    def load_config(self, environment: str) -> dict:
        """Load configuration for an environment."""
        config_path = self.config_dir / environment / "config.yaml"
        if not config_path.exists():
            raise FileNotFoundError(f"Config not found: {config_path}")

        with open(config_path) as f:
            return yaml.safe_load(f) or {}

    def load_all_configs(self) -> dict[str, dict]:
        """Load configurations for all environments."""
        configs = {}
        for env in self.environments:
            try:
                configs[env] = self.load_config(env)
            except FileNotFoundError:
                configs[env] = {}
        return configs

    def save_config(self, environment: str, config: dict) -> None:
        """Save configuration for an environment."""
        config_path = self.config_dir / environment / "config.yaml"
        config_path.parent.mkdir(parents=True, exist_ok=True)

        with open(config_path, "w") as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=True)

    def get_config_hash(self, environment: str) -> str:
        """Get hash of an environment's config for drift detection."""
        config = self.load_config(environment)
        config_str = json.dumps(config, sort_keys=True)
        return hashlib.sha256(config_str.encode()).hexdigest()[:12]


class ConfigValidator:
    """Validates configuration values and consistency."""

    REQUIRED_KEYS = {
        "app.name",
        "app.version",
        "logging.level",
        "database.host",
        "database.name",
    }

    ENVIRONMENT_CONSTRAINTS = {
        "production": {
            "logging.level": ["warning", "error", "critical"],
            "app.debug": [False],
            "database.ssl": [True],
        },
        "staging": {
            "database.ssl": [True],
        },
    }

    def validate(self, environment: str, config: dict) -> list[dict]:
        """Validate a configuration and return list of issues."""
        issues = []

        # Check required keys
        flat = self._flatten(config)
        for key in self.REQUIRED_KEYS:
            if key not in flat:
                issues.append(
                    {
                        "severity": "error",
                        "key": key,
                        "message": f"Required key '{key}' is missing",
                    }
                )

        # Check environment constraints
        constraints = self.ENVIRONMENT_CONSTRAINTS.get(environment, {})
        for key, allowed_values in constraints.items():
            if key in flat and flat[key] not in allowed_values:
                issues.append(
                    {
                        "severity": "error",
                        "key": key,
                        "message": f"Value '{flat[key]}' not allowed in {environment} (allowed: {allowed_values})",
                    }
                )

        # Check for potential secrets in plain text
        secret_patterns = ["password", "secret", "api_key", "token", "connection_string"]
        for key, value in flat.items():
            if any(p in key.lower() for p in secret_patterns):
                if isinstance(value, str) and not value.startswith("${"):
                    issues.append(
                        {
                            "severity": "warning",
                            "key": key,
                            "message": f"Potential secret in plain text (use variable references like ${{VAR_NAME}})",
                        }
                    )

        return issues

    def _flatten(self, d: dict, prefix: str = "") -> dict:
        """Flatten nested dict to dot-notation keys."""
        items = {}
        for k, v in d.items():
            new_key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                items.update(self._flatten(v, new_key))
            else:
                items[new_key] = v
        return items


class DriftDetector:
    """Detects configuration drift between environments."""

    def detect_drift(
        self, base_config: dict, target_config: dict, ignore_keys: Optional[list[str]] = None
    ) -> list[dict]:
        """Compare two configs and return differences."""
        ignore_keys = set(ignore_keys or [])
        diffs = []

        base_flat = self._flatten(base_config)
        target_flat = self._flatten(target_config)

        all_keys = set(base_flat.keys()) | set(target_flat.keys())

        for key in sorted(all_keys):
            if any(key.startswith(ik) for ik in ignore_keys):
                continue

            base_val = base_flat.get(key)
            target_val = target_flat.get(key)

            if base_val != target_val:
                if key not in base_flat:
                    diffs.append(
                        {"key": key, "type": "added", "base": None, "target": target_val}
                    )
                elif key not in target_flat:
                    diffs.append(
                        {"key": key, "type": "removed", "base": base_val, "target": None}
                    )
                else:
                    diffs.append(
                        {"key": key, "type": "changed", "base": base_val, "target": target_val}
                    )

        return diffs

    def _flatten(self, d: dict, prefix: str = "") -> dict:
        items = {}
        for k, v in d.items():
            new_key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                items.update(self._flatten(v, new_key))
            else:
                items[new_key] = v
        return items


# Sample config generation
def generate_sample_configs(config_dir: str) -> None:
    """Generate sample configuration files for all environments."""
    base_config = {
        "app": {
            "name": "azure-devops-utils",
            "version": "2.0.0",
            "debug": False,
        },
        "logging": {
            "level": "info",
            "format": "json",
            "output": "stdout",
        },
        "database": {
            "host": "localhost",
            "port": 5432,
            "name": "devops_db",
            "ssl": True,
            "pool_size": 10,
        },
        "cache": {
            "enabled": True,
            "ttl_seconds": 300,
            "backend": "redis",
        },
        "features": {
            "webhook_server": True,
            "compliance_checker": True,
            "cost_reports": False,
        },
    }

    env_overrides = {
        "dev": {
            "app": {"debug": True},
            "logging": {"level": "debug"},
            "database": {"host": "dev-db.internal", "ssl": False, "pool_size": 5},
            "cache": {"ttl_seconds": 60},
        },
        "staging": {
            "database": {"host": "staging-db.internal", "pool_size": 15},
            "cache": {"ttl_seconds": 120},
            "features": {"cost_reports": True},
        },
        "production": {
            "logging": {"level": "warning"},
            "database": {"host": "prod-db.internal", "pool_size": 50},
            "cache": {"ttl_seconds": 600},
            "features": {"cost_reports": True},
        },
    }

    store = ConfigStore(config_dir)
    for env in ["dev", "staging", "production"]:
        config = json.loads(json.dumps(base_config))
        _deep_merge(config, env_overrides.get(env, {}))
        store.save_config(env, config)
        console.print(f"  Generated config for [bold]{env}[/bold]")


def _deep_merge(base: dict, override: dict) -> None:
    """Deep merge override into base dict."""
    for key, value in override.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            _deep_merge(base[key], value)
        else:
            base[key] = value


@click.group()
def cli():
    """Multi-environment configuration manager."""
    pass


@cli.command()
@click.option("--config-dir", default="config", help="Configuration directory")
def init(config_dir: str):
    """Initialize sample configuration files."""
    console.print("[bold]Generating sample configurations...[/bold]")
    generate_sample_configs(config_dir)
    console.print("[green]Done![/green]")


@cli.command()
@click.option("--config-dir", default="config")
@click.option("--env", "environment", required=True, help="Environment to validate")
def validate(config_dir: str, environment: str):
    """Validate configuration for an environment."""
    store = ConfigStore(config_dir)
    validator = ConfigValidator()

    config = store.load_config(environment)
    issues = validator.validate(environment, config)

    if not issues:
        console.print(f"[green]✓ {environment} configuration is valid[/green]")
        return

    table = Table(title=f"Validation Issues: {environment}")
    table.add_column("Severity", width=10)
    table.add_column("Key", width=30)
    table.add_column("Message", width=50)

    for issue in issues:
        style = "red" if issue["severity"] == "error" else "yellow"
        table.add_row(
            f"[{style}]{issue['severity'].upper()}[/{style}]",
            issue["key"],
            issue["message"],
        )

    console.print(table)

    errors = sum(1 for i in issues if i["severity"] == "error")
    if errors > 0:
        sys.exit(1)


@cli.command()
@click.option("--config-dir", default="config")
@click.option("--base", "base_env", default="staging", help="Base environment")
@click.option("--target", "target_env", default="production", help="Target environment")
@click.option("--ignore", multiple=True, help="Keys to ignore in drift detection")
def drift(config_dir: str, base_env: str, target_env: str, ignore: tuple):
    """Detect configuration drift between environments."""
    store = ConfigStore(config_dir)
    detector = DriftDetector()

    base_config = store.load_config(base_env)
    target_config = store.load_config(target_env)

    diffs = detector.detect_drift(base_config, target_config, list(ignore))

    if not diffs:
        console.print(f"[green]✓ No drift between {base_env} and {target_env}[/green]")
        return

    table = Table(title=f"Config Drift: {base_env} → {target_env}")
    table.add_column("Type", width=10)
    table.add_column("Key", width=30)
    table.add_column(f"{base_env}", width=25)
    table.add_column(f"{target_env}", width=25)

    type_styles = {"added": "green", "removed": "red", "changed": "yellow"}

    for diff in diffs:
        style = type_styles[diff["type"]]
        table.add_row(
            f"[{style}]{diff['type']}[/{style}]",
            diff["key"],
            str(diff["base"] or "-"),
            str(diff["target"] or "-"),
        )

    console.print(table)
    console.print(f"\n[bold]{len(diffs)} differences found[/bold]")


@cli.command()
@click.option("--config-dir", default="config")
def show(config_dir: str):
    """Show configuration tree for all environments."""
    store = ConfigStore(config_dir)
    configs = store.load_all_configs()

    for env, config in configs.items():
        tree = Tree(f"[bold cyan]{env}[/bold cyan] (hash: {store.get_config_hash(env)})")
        _build_tree(tree, config)
        console.print(tree)
        console.print()


def _build_tree(tree: Tree, data: dict, depth: int = 0) -> None:
    """Build rich tree from nested dict."""
    for key, value in sorted(data.items()):
        if isinstance(value, dict):
            branch = tree.add(f"[bold]{key}[/bold]")
            _build_tree(branch, value, depth + 1)
        else:
            tree.add(f"{key}: [dim]{value}[/dim]")


if __name__ == "__main__":
    cli()
