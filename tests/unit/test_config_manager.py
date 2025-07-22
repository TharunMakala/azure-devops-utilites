"""Unit tests for the configuration manager."""

import sys
from pathlib import Path

import pytest
import yaml

# Add tools to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "tools" / "config-manager"))

from config_manager import ConfigStore, ConfigValidator, DriftDetector


class TestConfigStore:
    def test_load_config(self, tmp_config_dir):
        store = ConfigStore(str(tmp_config_dir))
        config = store.load_config("dev")
        assert config["app"]["name"] == "test-app"
        assert config["app"]["debug"] is True

    def test_load_config_not_found(self, tmp_path):
        store = ConfigStore(str(tmp_path))
        with pytest.raises(FileNotFoundError):
            store.load_config("nonexistent")

    def test_load_all_configs(self, tmp_config_dir):
        store = ConfigStore(str(tmp_config_dir))
        configs = store.load_all_configs()
        assert "dev" in configs
        assert "staging" in configs
        assert "production" in configs

    def test_save_and_load_config(self, tmp_path):
        store = ConfigStore(str(tmp_path))
        config = {"app": {"name": "test", "version": "2.0.0"}}
        store.save_config("test-env", config)

        loaded = store.load_config("test-env")
        assert loaded == config

    def test_config_hash_changes(self, tmp_config_dir):
        store = ConfigStore(str(tmp_config_dir))
        hash_dev = store.get_config_hash("dev")
        hash_prod = store.get_config_hash("production")
        assert hash_dev != hash_prod

    def test_config_hash_stable(self, tmp_config_dir):
        store = ConfigStore(str(tmp_config_dir))
        hash1 = store.get_config_hash("dev")
        hash2 = store.get_config_hash("dev")
        assert hash1 == hash2


class TestConfigValidator:
    def test_valid_config(self, tmp_config_dir):
        store = ConfigStore(str(tmp_config_dir))
        validator = ConfigValidator()
        config = store.load_config("staging")
        issues = validator.validate("staging", config)
        # Staging should have no errors (has all required keys, meets constraints)
        errors = [i for i in issues if i["severity"] == "error"]
        assert len(errors) == 0

    def test_missing_required_keys(self):
        validator = ConfigValidator()
        config = {"app": {"name": "test"}}
        issues = validator.validate("dev", config)
        missing = [i for i in issues if "missing" in i["message"].lower()]
        assert len(missing) > 0

    def test_production_constraints_debug(self):
        validator = ConfigValidator()
        config = {
            "app": {"name": "test", "version": "1.0", "debug": True},
            "logging": {"level": "debug"},
            "database": {"host": "db", "name": "test", "ssl": True},
        }
        issues = validator.validate("production", config)
        errors = [i for i in issues if i["severity"] == "error"]
        assert any("debug" in e["key"] for e in errors)

    def test_secret_in_plaintext_warning(self):
        validator = ConfigValidator()
        config = {
            "app": {"name": "test", "version": "1.0"},
            "logging": {"level": "info"},
            "database": {
                "host": "db",
                "name": "test",
                "password": "my-secret-password",
            },
        }
        issues = validator.validate("dev", config)
        warnings = [i for i in issues if i["severity"] == "warning"]
        assert any("password" in w["key"] for w in warnings)

    def test_secret_reference_no_warning(self):
        validator = ConfigValidator()
        config = {
            "app": {"name": "test", "version": "1.0"},
            "logging": {"level": "info"},
            "database": {
                "host": "db",
                "name": "test",
                "password": "${DB_PASSWORD}",
            },
        }
        issues = validator.validate("dev", config)
        warnings = [i for i in issues if "password" in i.get("key", "")]
        assert len(warnings) == 0


class TestDriftDetector:
    def test_no_drift_same_config(self):
        detector = DriftDetector()
        config = {"app": {"name": "test"}, "db": {"host": "localhost"}}
        diffs = detector.detect_drift(config, config)
        assert len(diffs) == 0

    def test_detect_changed_values(self):
        detector = DriftDetector()
        base = {"app": {"name": "test", "debug": True}}
        target = {"app": {"name": "test", "debug": False}}
        diffs = detector.detect_drift(base, target)
        assert len(diffs) == 1
        assert diffs[0]["type"] == "changed"
        assert diffs[0]["key"] == "app.debug"

    def test_detect_added_keys(self):
        detector = DriftDetector()
        base = {"app": {"name": "test"}}
        target = {"app": {"name": "test", "version": "2.0"}}
        diffs = detector.detect_drift(base, target)
        assert len(diffs) == 1
        assert diffs[0]["type"] == "added"

    def test_detect_removed_keys(self):
        detector = DriftDetector()
        base = {"app": {"name": "test", "deprecated": True}}
        target = {"app": {"name": "test"}}
        diffs = detector.detect_drift(base, target)
        assert len(diffs) == 1
        assert diffs[0]["type"] == "removed"

    def test_ignore_keys(self):
        detector = DriftDetector()
        base = {"app": {"name": "test"}, "logging": {"level": "debug"}}
        target = {"app": {"name": "test"}, "logging": {"level": "warning"}}
        diffs = detector.detect_drift(base, target, ignore_keys=["logging"])
        assert len(diffs) == 0

    def test_drift_between_environments(self, tmp_config_dir):
        store = ConfigStore(str(tmp_config_dir))
        detector = DriftDetector()
        dev = store.load_config("dev")
        prod = store.load_config("production")
        diffs = detector.detect_drift(dev, prod)
        assert len(diffs) > 0  # Dev and prod should differ
