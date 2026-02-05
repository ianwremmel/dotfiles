"""Shared library for Claude Code Bash hooks.

Provides command parsing, configuration loading, task runner detection,
and rule matching for PreToolUse and PostToolUse hooks.
"""

import os
import shlex
from pathlib import Path
from typing import Optional

import bashlex
import bashlex.errors
import yaml


def action_past_tense(action: str) -> str:
    """Convert action to past tense for readable messages."""
    if action == 'deny':
        return 'denied'
    if action == 'allow':
        return 'allowed'
    return action


def get_config_path() -> Path:
    """Return path to the bash.yml configuration file."""
    hooks_dir = Path(__file__).parent.parent
    return hooks_dir / "pre-tool-use" / "bash.yml"


def load_config(config_path: Optional[Path] = None) -> dict:
    """Load and return the YAML configuration."""
    if config_path is None:
        config_path = get_config_path()
    with open(config_path) as f:
        return yaml.safe_load(f)


def expand_path(path: str) -> str:
    """Expand environment variables and ~ in paths."""
    return os.path.expandvars(os.path.expanduser(path))


def _extract_command_text(node, source: str) -> str | None:
    """Extract the original text for a command node, excluding env var assignments.

    Returns the command text starting from the first word (after any assignments),
    or None if there's no actual command (just assignments).
    """
    first_word_pos = None
    for part in node.parts:
        if part.kind == 'word':
            first_word_pos = part.pos[0]
            break

    if first_word_pos is None:
        return None

    end = node.pos[1]
    return source[first_word_pos:end]


def split_compound_command(command: str) -> list[str]:
    """Split command on &&, ||, ;, |, newline using bashlex AST.

    Returns list of individual command segments with env vars stripped.
    Handles comments, subshells, and all bash syntax via the bashlex parser.
    """
    if not command or not command.strip():
        return []

    try:
        parts = bashlex.parse(command)
    except bashlex.errors.ParsingError:
        # If bashlex can't parse it, return as single command
        return [command.strip()]

    commands = []

    def visit(node):
        if node.kind == 'command':
            cmd_text = _extract_command_text(node, command)
            if cmd_text:
                commands.append(cmd_text)
        elif node.kind in ('list', 'pipeline', 'compound'):
            if hasattr(node, 'parts'):
                for part in node.parts:
                    if hasattr(part, 'kind'):
                        visit(part)
            if hasattr(node, 'list'):
                for item in node.list:
                    if hasattr(item, 'kind'):
                        visit(item)

    for part in parts:
        visit(part)

    return commands


def parse_command(command: str) -> dict:
    """Parse a command string into structured components.

    Returns dict with:
        - base_command: The main command (e.g., 'git')
        - subcommand: First argument if applicable (e.g., 'push')
        - args: List of all arguments
        - switches: List of switch/flag arguments (starting with -)
        - original: Original command string
    """
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()

    if not parts:
        return {
            'base_command': '',
            'subcommand': None,
            'args': [],
            'switches': [],
            'original': command,
        }

    base_command = parts[0]
    args = parts[1:] if len(parts) > 1 else []
    subcommand = args[0] if args and not args[0].startswith('-') else None
    switches = [arg for arg in args if arg.startswith('-')]

    return {
        'base_command': base_command,
        'subcommand': subcommand,
        'args': args,
        'switches': switches,
        'original': command,
    }


def detect_task_runner(parsed: dict, config: dict) -> Optional[dict]:
    """Detect if command is a task runner and extract effective command.

    Task runners:
        - Simple (npx, uvx, bunx): First arg is the actual command
        - Nested (npm run, yarn dlx): Subcommand triggers task runner mode

    Returns None if not a task runner, otherwise returns parsed effective command.
    """
    task_runners = config.get('taskRunners', {})
    simple_runners = task_runners.get('simple', [])
    nested_runners = task_runners.get('nested', {})

    base = parsed['base_command']
    args = parsed['args']

    if base in simple_runners and args:
        effective_command = ' '.join(args)
        return parse_command(effective_command)

    if base in nested_runners:
        trigger_subcommands = nested_runners[base]
        if parsed['subcommand'] in trigger_subcommands and len(args) > 1:
            effective_command = ' '.join(args[1:])
            return parse_command(effective_command)

    return None


def match_switches(switches: list[str], rule_switches: list[str]) -> bool:
    """Check if command switches match rule switches.

    Returns True if ALL rule switches are present in command switches.
    """
    for rule_switch in rule_switches:
        found = False
        for cmd_switch in switches:
            if cmd_switch == rule_switch:
                found = True
                break
            if cmd_switch.startswith(rule_switch + '='):
                found = True
                break
            if '=' in rule_switch:
                if cmd_switch == rule_switch.split('=')[0]:
                    found = True
                    break
        if not found:
            return False
    return True


def match_command(parsed: dict, config: dict, is_task_runner: bool = False) -> dict:
    """Match parsed command against configuration rules.

    Returns dict with:
        - action: 'allow', 'deny', or 'ask'
        - reason: Explanation of the decision
        - matched_rule: The rule that matched (for logging)
    """
    commands = config.get('commands', {})
    base = parsed['base_command']
    subcommand = parsed['subcommand']
    switches = parsed['switches']

    if base not in commands:
        return {
            'action': 'ask',
            'reason': f"Command '{base}' has no configured rules",
            'matched_rule': None,
        }

    cmd_config = commands[base]
    default_action = cmd_config.get('action', 'ask')

    if subcommand and 'subcommands' in cmd_config:
        subcmd_config = cmd_config['subcommands'].get(subcommand)
        if subcmd_config:
            subcmd_action = subcmd_config.get('action', default_action)
            subcmd_rules = subcmd_config.get('rules', [])

            for rule in subcmd_rules:
                rule_switches = rule.get('switches', [])
                if match_switches(switches, rule_switches):
                    action = rule.get('action', subcmd_action)
                    switch_str = ', '.join(f"'{s}'" for s in rule_switches)
                    task_runner_suffix = " (via task runner)" if is_task_runner else ""
                    return {
                        'action': action,
                        'reason': f"Command '{base} {subcommand}' with {switch_str} is {action_past_tense(action)}{task_runner_suffix}",
                        'matched_rule': {'command': base, 'subcommand': subcommand, 'switches': rule_switches},
                    }

            if subcmd_rules:
                required_switches = []
                for rule in subcmd_rules:
                    if rule.get('action') == 'allow':
                        required_switches.extend(rule.get('switches', []))
                if required_switches and subcmd_action == 'deny':
                    switch_str = ', '.join(f"'{s}'" for s in required_switches)
                    return {
                        'action': 'deny',
                        'reason': f"Command '{base} {subcommand}' requires one of: {switch_str}",
                        'matched_rule': {'command': base, 'subcommand': subcommand, 'requires': required_switches},
                    }

            task_runner_suffix = " (via task runner)" if is_task_runner else ""
            return {
                'action': subcmd_action,
                'reason': f"Command '{base} {subcommand}' is {action_past_tense(subcmd_action)}{task_runner_suffix}",
                'matched_rule': {'command': base, 'subcommand': subcommand},
            }

    rules = cmd_config.get('rules', [])
    for rule in rules:
        rule_switches = rule.get('switches', [])
        if match_switches(switches, rule_switches):
            action = rule.get('action', default_action)
            switch_str = ', '.join(f"'{s}'" for s in rule_switches)
            task_runner_suffix = " (via task runner)" if is_task_runner else ""
            return {
                'action': action,
                'reason': f"Command '{base}' with {switch_str} is {action_past_tense(action)}{task_runner_suffix}",
                'matched_rule': {'command': base, 'switches': rule_switches},
            }

    task_runner_suffix = " (via task runner)" if is_task_runner else ""
    return {
        'action': default_action,
        'reason': f"Command '{base}' is {action_past_tense(default_action)}{task_runner_suffix}",
        'matched_rule': {'command': base},
    }


def evaluate_command(command: str, config: dict) -> dict:
    """Evaluate a full command string against configuration.

    Handles:
        - Environment variable stripping (via bashlex)
        - Compound command splitting
        - Task runner detection
        - Rule matching

    Returns dict with:
        - action: 'allow', 'deny', or 'ask'
        - reason: Explanation of the decision
        - commands: List of evaluated command segments
    """
    segments = split_compound_command(command)

    if not segments:
        return {
            'action': 'ask',
            'reason': 'Empty command',
            'commands': [],
        }

    results = []
    is_compound = len(segments) > 1

    for segment in segments:
        parsed = parse_command(segment)
        effective = detect_task_runner(parsed, config)
        is_task_runner = effective is not None

        if effective:
            match_result = match_command(effective, config, is_task_runner=True)
        else:
            match_result = match_command(parsed, config, is_task_runner=False)

        results.append({
            'segment': segment,
            'parsed': parsed,
            'effective': effective,
            'is_task_runner': is_task_runner,
            'match': match_result,
        })

    final_action = 'allow'
    reasons = []

    for result in results:
        action = result['match']['action']
        reason = result['match']['reason']

        if is_compound:
            reason = f"{reason} (in compound command)"

        if action == 'deny':
            final_action = 'deny'
            reasons.append(reason)
        elif action == 'ask' and final_action == 'allow':
            final_action = 'ask'
            reasons.append(reason)
        elif final_action == 'allow':
            reasons.append(reason)

    if final_action == 'deny':
        reason_text = '; '.join(r for r in reasons if 'denied' in r or 'requires' in r)
    elif final_action == 'ask':
        reason_text = '; '.join(r for r in reasons if 'no configured rules' in r or 'ask' in r)
        if not reason_text:
            reason_text = reasons[0] if reasons else 'Unknown command'
    else:
        reason_text = reasons[0] if reasons else 'Command allowed'

    return {
        'action': final_action,
        'reason': reason_text,
        'commands': results,
    }
