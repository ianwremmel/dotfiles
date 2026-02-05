"""Tests for bash_common.py shared library."""

import pytest
from pathlib import Path

from bash_common import (
    split_compound_command,
    parse_command,
    detect_task_runner,
    match_switches,
    match_command,
    evaluate_command,
    load_config,
)


class TestSplitCompoundCommand:
    """Tests for split_compound_command function."""

    def test_single_command(self):
        assert split_compound_command("git status") == ["git status"]

    def test_and_operator(self):
        assert split_compound_command("git add . && git commit") == ["git add .", "git commit"]

    def test_or_operator(self):
        assert split_compound_command("cmd1 || cmd2") == ["cmd1", "cmd2"]

    def test_semicolon(self):
        assert split_compound_command("pwd; ls") == ["pwd", "ls"]

    def test_pipe(self):
        assert split_compound_command("git log | head") == ["git log", "head"]

    def test_quoted_string_with_operators(self):
        result = split_compound_command('echo "hello && world"')
        assert result == ['echo "hello && world"']

    def test_single_quoted_string(self):
        result = split_compound_command("echo 'test | pipe'")
        assert result == ["echo 'test | pipe'"]

    def test_mixed_operators(self):
        result = split_compound_command("a && b || c; d | e")
        assert result == ["a", "b", "c", "d", "e"]

    def test_escaped_chars(self):
        result = split_compound_command("echo hello\\&\\&world")
        assert result == ["echo hello\\&\\&world"]

    def test_env_vars_stripped(self):
        # bashlex strips env vars from commands during extraction
        result = split_compound_command("DEBUG=1 npm run build")
        assert result == ["npm run build"]

    def test_multiple_env_vars_stripped(self):
        result = split_compound_command("FOO=bar BAZ=qux git status")
        assert result == ["git status"]

    def test_env_vars_only(self):
        # Assignment-only commands return nothing (no actual command)
        result = split_compound_command("FOO=bar")
        assert result == []

    def test_comment_stripped(self):
        result = split_compound_command("echo hello # comment")
        assert result == ["echo hello"]

    def test_subshell(self):
        result = split_compound_command("(cd /tmp && ls)")
        assert result == ["cd /tmp", "ls"]

    def test_line_continuation(self):
        # bashlex handles line continuation - the command is parsed as single command
        result = split_compound_command("echo hello \\\nworld")
        # Note: bashlex preserves the original text including escape chars
        assert len(result) == 1
        assert "echo" in result[0] and "world" in result[0]


class TestParseCommand:
    """Tests for parse_command function."""

    def test_simple_command(self):
        result = parse_command("git")
        assert result["base_command"] == "git"
        assert result["subcommand"] is None
        assert result["args"] == []
        assert result["switches"] == []

    def test_command_with_subcommand(self):
        result = parse_command("git push origin main")
        assert result["base_command"] == "git"
        assert result["subcommand"] == "push"
        assert result["args"] == ["push", "origin", "main"]

    def test_command_with_switches(self):
        result = parse_command("git push --force origin")
        assert result["base_command"] == "git"
        assert result["subcommand"] == "push"
        assert result["switches"] == ["--force"]

    def test_switch_as_first_arg(self):
        result = parse_command("ls -la")
        assert result["base_command"] == "ls"
        assert result["subcommand"] is None
        assert result["switches"] == ["-la"]

    def test_preserves_original(self):
        original = "git commit -m 'test message'"
        result = parse_command(original)
        assert result["original"] == original


class TestDetectTaskRunner:
    """Tests for detect_task_runner function."""

    @pytest.fixture
    def config(self):
        return {
            "taskRunners": {
                "simple": ["npx", "uvx", "bunx"],
                "nested": {
                    "npm": ["run", "exec"],
                    "yarn": ["run", "dlx"],
                },
            }
        }

    def test_simple_task_runner(self, config):
        parsed = parse_command("npx eslint src/")
        result = detect_task_runner(parsed, config)
        assert result is not None
        assert result["base_command"] == "eslint"

    def test_nested_task_runner_npm_run(self, config):
        parsed = parse_command("npm run test")
        result = detect_task_runner(parsed, config)
        assert result is not None
        assert result["base_command"] == "test"

    def test_nested_task_runner_yarn_dlx(self, config):
        parsed = parse_command("yarn dlx create-app my-app")
        result = detect_task_runner(parsed, config)
        assert result is not None
        assert result["base_command"] == "create-app"

    def test_not_task_runner_npm_install(self, config):
        parsed = parse_command("npm install lodash")
        result = detect_task_runner(parsed, config)
        assert result is None

    def test_not_task_runner_unknown(self, config):
        parsed = parse_command("unknown command")
        result = detect_task_runner(parsed, config)
        assert result is None

    def test_simple_task_runner_no_args(self, config):
        parsed = parse_command("npx")
        result = detect_task_runner(parsed, config)
        assert result is None


class TestMatchSwitches:
    """Tests for match_switches function."""

    def test_exact_match(self):
        assert match_switches(["--force"], ["--force"]) is True

    def test_multiple_switches(self):
        assert match_switches(["--force", "--verbose"], ["--force"]) is True

    def test_missing_switch(self):
        assert match_switches(["--verbose"], ["--force"]) is False

    def test_switch_with_value(self):
        assert match_switches(["--output=file.txt"], ["--output"]) is True

    def test_all_required(self):
        assert match_switches(["--force"], ["--force", "--verbose"]) is False

    def test_empty_rule_switches(self):
        assert match_switches(["--force"], []) is True

    def test_empty_command_switches(self):
        assert match_switches([], ["--force"]) is False


class TestMatchCommand:
    """Tests for match_command function."""

    @pytest.fixture
    def config(self):
        return {
            "commands": {
                "git": {
                    "action": "allow",
                    "rules": [
                        {"switches": ["--force"], "action": "deny"},
                    ],
                    "subcommands": {
                        "push": {
                            "action": "allow",
                            "rules": [
                                {"switches": ["--force-with-lease"], "action": "allow"},
                                {"switches": ["--force"], "action": "deny"},
                            ],
                        },
                        "reset": {
                            "action": "ask",
                            "rules": [
                                {"switches": ["--hard"], "action": "deny"},
                            ],
                        },
                    },
                },
                "kubectl": {
                    "action": "deny",
                    "subcommands": {
                        "run": {
                            "action": "deny",
                            "rules": [
                                {"switches": ["--rm"], "action": "allow"},
                            ],
                        },
                    },
                },
            }
        }

    def test_allowed_command(self, config):
        parsed = parse_command("git status")
        result = match_command(parsed, config)
        assert result["action"] == "allow"

    def test_denied_by_switch(self, config):
        parsed = parse_command("git push --force")
        result = match_command(parsed, config)
        assert result["action"] == "deny"

    def test_allowed_with_specific_switch(self, config):
        parsed = parse_command("git push --force-with-lease")
        result = match_command(parsed, config)
        assert result["action"] == "allow"

    def test_subcommand_default_action(self, config):
        parsed = parse_command("git reset HEAD")
        result = match_command(parsed, config)
        assert result["action"] == "ask"

    def test_unknown_command(self, config):
        parsed = parse_command("unknown-cmd")
        result = match_command(parsed, config)
        assert result["action"] == "ask"
        assert "no configured rules" in result["reason"]

    def test_requires_switch(self, config):
        parsed = parse_command("kubectl run test --image=alpine")
        result = match_command(parsed, config)
        assert result["action"] == "deny"
        assert "--rm" in result["reason"]


class TestEvaluateCommand:
    """Integration tests for evaluate_command function."""

    @pytest.fixture
    def config(self):
        return {
            "taskRunners": {
                "simple": ["npx"],
                "nested": {"npm": ["run"]},
            },
            "commands": {
                "git": {"action": "allow"},
                "rm": {"action": "deny"},
                "eslint": {"action": "allow"},
            },
        }

    def test_simple_allowed(self, config):
        result = evaluate_command("git status", config)
        assert result["action"] == "allow"

    def test_simple_denied(self, config):
        result = evaluate_command("rm file.txt", config)
        assert result["action"] == "deny"

    def test_env_vars_stripped(self, config):
        result = evaluate_command("DEBUG=1 git status", config)
        assert result["action"] == "allow"

    def test_compound_with_denied(self, config):
        result = evaluate_command("git status && rm file.txt", config)
        assert result["action"] == "deny"

    def test_task_runner(self, config):
        result = evaluate_command("npx eslint src/", config)
        assert result["action"] == "allow"
        assert "eslint" in result["reason"]

    def test_empty_command(self, config):
        result = evaluate_command("", config)
        assert result["action"] == "ask"


class TestLoadConfig:
    """Tests for configuration loading."""

    def test_load_real_config(self):
        config = load_config()
        assert "commands" in config
        assert "taskRunners" in config
        assert "logging" in config

    def test_load_custom_config(self, tmp_path):
        config_file = tmp_path / "test.yml"
        config_file.write_text("""
commands:
  test:
    action: allow
taskRunners:
  simple: [npx]
  nested: {}
""")
        config = load_config(config_file)
        assert config["commands"]["test"]["action"] == "allow"
