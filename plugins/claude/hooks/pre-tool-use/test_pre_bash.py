"""Tests for PreToolUse bash hook."""

import json
import subprocess
import sys
from pathlib import Path

import pytest
import yaml


HOOK_PATH = Path(__file__).parent / "bash"
FIXTURES_PATH = Path(__file__).parent / "fixtures.yml"


def run_hook(command: str, tool_use_id: str = "test-123") -> dict:
    """Run the hook with given command and return parsed output."""
    input_data = {
        "tool_input": {"command": command},
        "tool_use_id": tool_use_id,
    }

    result = subprocess.run(
        [sys.executable, str(HOOK_PATH)],
        input=json.dumps(input_data),
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        raise RuntimeError(f"Hook failed: {result.stderr}")

    output = json.loads(result.stdout)
    # Extract hookSpecificOutput if present (the actual hook format)
    if "hookSpecificOutput" in output:
        return output["hookSpecificOutput"]
    return output


def load_fixtures():
    """Load test fixtures from YAML file."""
    with open(FIXTURES_PATH) as f:
        data = yaml.safe_load(f)
    return data.get("fixtures", [])


class TestPreToolUseHook:
    """Tests for the PreToolUse hook script."""

    def test_hook_returns_json(self):
        result = run_hook("git status")
        assert "permissionDecision" in result
        assert "permissionDecisionReason" in result

    def test_allowed_command(self):
        result = run_hook("git status")
        assert result["permissionDecision"] == "allow"

    def test_denied_command(self):
        result = run_hook("rm file.txt")
        assert result["permissionDecision"] == "deny"

    def test_unknown_command_asks(self):
        result = run_hook("some-unknown-command")
        assert result["permissionDecision"] == "ask"

    def test_empty_command_denied(self):
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps({"tool_input": {"command": ""}}),
            capture_output=True,
            text=True,
        )
        output = json.loads(result.stdout)
        # Handle hookSpecificOutput wrapper
        if "hookSpecificOutput" in output:
            output = output["hookSpecificOutput"]
        assert output["permissionDecision"] == "deny"

    def test_missing_command_denied(self):
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input=json.dumps({"tool_input": {}}),
            capture_output=True,
            text=True,
        )
        output = json.loads(result.stdout)
        # Handle hookSpecificOutput wrapper
        if "hookSpecificOutput" in output:
            output = output["hookSpecificOutput"]
        assert output["permissionDecision"] == "deny"

    def test_invalid_json_denied(self):
        result = subprocess.run(
            [sys.executable, str(HOOK_PATH)],
            input="not valid json",
            capture_output=True,
            text=True,
        )
        output = json.loads(result.stdout)
        # Handle hookSpecificOutput wrapper
        if "hookSpecificOutput" in output:
            output = output["hookSpecificOutput"]
        assert output["permissionDecision"] == "deny"


class TestFixtures:
    """Run all fixtures from fixtures.yml."""

    @pytest.fixture
    def fixtures(self):
        return load_fixtures()

    def test_fixtures_exist(self, fixtures):
        assert len(fixtures) > 0, "No fixtures found in fixtures.yml"

    @pytest.mark.parametrize(
        "fixture",
        load_fixtures(),
        ids=lambda f: f.get("input", "unnamed"),
    )
    def test_fixture(self, fixture):
        command = fixture["input"]
        expected_action = fixture["action"]
        expected_commands = fixture["commands"]

        result = run_hook(command)

        assert result["permissionDecision"] == expected_action, (
            f"Command '{command}' expected {expected_action}, got {result['permissionDecision']}. "
            f"Reason: {result['permissionDecisionReason']}"
        )


class TestGitCommands:
    """Detailed tests for git command handling."""

    def test_git_status(self):
        result = run_hook("git status")
        assert result["permissionDecision"] == "allow"

    def test_git_push_normal(self):
        result = run_hook("git push origin main")
        assert result["permissionDecision"] == "allow"

    def test_git_push_force_denied(self):
        result = run_hook("git push --force origin main")
        assert result["permissionDecision"] == "deny"
        assert "--force" in result["permissionDecisionReason"]

    def test_git_push_force_with_lease_allowed(self):
        result = run_hook("git push --force-with-lease origin main")
        assert result["permissionDecision"] == "allow"

    def test_git_reset_hard_denied(self):
        result = run_hook("git reset --hard HEAD")
        assert result["permissionDecision"] == "deny"

    def test_git_reset_soft_allowed(self):
        result = run_hook("git reset --soft HEAD")
        assert result["permissionDecision"] == "allow"


class TestTaskRunners:
    """Tests for task runner detection."""

    def test_npx_eslint(self):
        result = run_hook("npx eslint src/")
        assert result["permissionDecision"] == "allow"
        assert "eslint" in result["permissionDecisionReason"]

    def test_npm_run(self):
        result = run_hook("npm run build")
        # npm is allowed by default (run scripts are trusted per config comment)
        assert result["permissionDecision"] == "allow"

    def test_npm_install_not_task_runner(self):
        result = run_hook("npm install")
        assert result["permissionDecision"] == "allow"


class TestCompoundCommands:
    """Tests for compound command handling."""

    def test_and_both_allowed(self):
        result = run_hook("git status && git diff")
        assert result["permissionDecision"] == "allow"

    def test_and_one_denied(self):
        result = run_hook("git status && rm file")
        assert result["permissionDecision"] == "deny"

    def test_pipe_command(self):
        result = run_hook("git log | head")
        assert result["permissionDecision"] == "allow"

    def test_semicolon(self):
        result = run_hook("pwd; ls")
        assert result["permissionDecision"] == "allow"


class TestEnvironmentVariables:
    """Tests for environment variable handling."""

    def test_env_var_stripped(self):
        result = run_hook("DEBUG=1 git status")
        assert result["permissionDecision"] == "allow"

    def test_multiple_env_vars(self):
        result = run_hook("FOO=bar BAZ=qux git status")
        assert result["permissionDecision"] == "allow"
