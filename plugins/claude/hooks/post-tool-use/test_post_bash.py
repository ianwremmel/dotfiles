"""Tests for PostToolUse bash hook."""

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from unittest import mock

import pytest
import yaml


HOOK_PATH = Path(__file__).parent / "bash"


class TestPostToolUseFunctions:
    """Unit tests for PostToolUse functions."""

    def test_import_modules(self):
        """Verify we can import the shared library."""
        sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
        from bash_common import parse_command, strip_env_vars
        assert callable(parse_command)
        assert callable(strip_env_vars)


class TestAddAllowRule:
    """Tests for add_allow_rule function."""

    @pytest.fixture
    def temp_config(self, tmp_path):
        """Create a temporary config file."""
        config_file = tmp_path / "bash.yml"
        config_file.write_text(yaml.dump({
            "logging": {"enabled": False},
            "taskRunners": {"simple": [], "nested": {}},
            "commands": {
                "git": {"action": "allow"},
                "rm": {"action": "deny"},
            },
        }))
        return config_file

    def test_add_new_command(self, temp_config):
        """Test adding a rule for a new command."""
        sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
        sys.path.insert(0, str(Path(__file__).parent))

        from bash_common import load_config

        # Manually add the rule
        with open(temp_config) as f:
            config = yaml.safe_load(f)

        config["commands"]["newcmd"] = {"action": "allow"}

        with open(temp_config, "w") as f:
            yaml.dump(config, f)

        updated_config = load_config(temp_config)
        assert "newcmd" in updated_config["commands"]
        assert updated_config["commands"]["newcmd"]["action"] == "allow"

    def test_add_subcommand(self, temp_config):
        """Test adding a subcommand rule."""
        with open(temp_config) as f:
            config = yaml.safe_load(f)

        config["commands"]["git"]["subcommands"] = {
            "newsubcmd": {"action": "allow"}
        }

        with open(temp_config, "w") as f:
            yaml.dump(config, f)

        with open(temp_config) as f:
            updated = yaml.safe_load(f)

        assert "subcommands" in updated["commands"]["git"]
        assert "newsubcmd" in updated["commands"]["git"]["subcommands"]


class TestFindPendingApproval:
    """Tests for finding pending approval entries in logs."""

    @pytest.fixture
    def temp_log(self, tmp_path):
        """Create a temporary log file."""
        log_file = tmp_path / "bash.log"
        entries = [
            {"timestamp": "2024-01-01T12:00:00", "command": "cmd1", "action": "allow", "tool_use_id": "id-1"},
            {"timestamp": "2024-01-01T12:00:01", "command": "cmd2", "action": "ask", "tool_use_id": "id-2"},
            {"timestamp": "2024-01-01T12:00:02", "command": "cmd3", "action": "deny", "tool_use_id": "id-3"},
        ]
        with open(log_file, "w") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")
        return log_file

    def test_find_pending(self, temp_log):
        """Test finding a pending approval entry."""
        found = None
        with open(temp_log) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get("tool_use_id") == "id-2" and entry.get("action") == "ask":
                    found = entry
                    break

        assert found is not None
        assert found["command"] == "cmd2"

    def test_not_find_allowed(self, temp_log):
        """Test that allowed entries are not found as pending."""
        found = None
        with open(temp_log) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get("tool_use_id") == "id-1" and entry.get("action") == "ask":
                    found = entry
                    break

        assert found is None

    def test_not_find_missing(self, temp_log):
        """Test behavior with missing tool_use_id."""
        found = None
        with open(temp_log) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get("tool_use_id") == "id-nonexistent":
                    found = entry
                    break

        assert found is None


class TestPostToolUseHook:
    """Integration tests for PostToolUse hook script."""

    def test_hook_handles_no_pending(self):
        """Test hook does nothing when no pending approval."""
        input_data = {
            "tool_input": {"command": "git status"},
            "tool_use_id": "test-no-pending",
            "tool_result": {"is_error": False},
        }

        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps(input_data),
            capture_output=True,
            text=True,
        )

        # Should complete without error
        assert result.returncode == 0

    def test_hook_handles_error_result(self):
        """Test hook does nothing when command errored."""
        input_data = {
            "tool_input": {"command": "git status"},
            "tool_use_id": "test-error",
            "tool_result": {"is_error": True},
        }

        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps(input_data),
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0

    def test_hook_handles_invalid_json(self):
        """Test hook handles invalid JSON gracefully."""
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input="not valid json",
            capture_output=True,
            text=True,
        )

        # Should complete without error
        assert result.returncode == 0

    def test_hook_handles_missing_fields(self):
        """Test hook handles missing fields gracefully."""
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps({}),
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0


class TestConfigUpdate:
    """Tests for config update functionality."""

    def test_yaml_round_trip(self, tmp_path):
        """Test that YAML can be loaded and saved without corruption."""
        config_file = tmp_path / "test.yml"
        original = {
            "logging": {"enabled": True, "path": "/tmp/log"},
            "commands": {
                "git": {
                    "action": "allow",
                    "subcommands": {"push": {"action": "allow"}},
                },
            },
        }

        with open(config_file, "w") as f:
            yaml.dump(original, f, default_flow_style=False, sort_keys=False)

        with open(config_file) as f:
            loaded = yaml.safe_load(f)

        assert loaded == original

    def test_add_to_existing_commands(self, tmp_path):
        """Test adding a new command to existing config."""
        config_file = tmp_path / "test.yml"
        with open(config_file, "w") as f:
            yaml.dump({
                "commands": {"git": {"action": "allow"}},
            }, f)

        with open(config_file) as f:
            config = yaml.safe_load(f)

        config["commands"]["newcmd"] = {"action": "allow"}

        with open(config_file, "w") as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)

        with open(config_file) as f:
            updated = yaml.safe_load(f)

        assert "git" in updated["commands"]
        assert "newcmd" in updated["commands"]
