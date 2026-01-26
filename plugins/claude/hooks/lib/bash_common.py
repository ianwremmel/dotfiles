"""Shared library for Claude Code Bash hooks.

Provides command parsing, configuration loading, task runner detection,
and rule matching for PreToolUse and PostToolUse hooks.
"""

import os
import re
import shlex
from pathlib import Path
from typing import Optional

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


def strip_env_vars(command: str) -> str:
    """Strip leading environment variable assignments from command.

    Examples:
        X=1 Y=2 npm run → npm run
        FOO=bar echo test → echo test
    """
    pattern = r'^(\s*[A-Za-z_][A-Za-z0-9_]*=[^\s]*\s+)+'
    return re.sub(pattern, '', command).strip()


def strip_comments(command: str) -> str:
    """Strip bash comments from command.

    Comments start with # and continue to end of line, but only when
    # is not inside quotes.

    Examples:
        # comment → (empty)
        echo foo # comment → echo foo
        echo "# not a comment" → echo "# not a comment"
    """
    result = []
    in_single_quote = False
    in_double_quote = False
    in_comment = False
    i = 0

    while i < len(command):
        char = command[i]

        if in_comment:
            if char == '\n':
                in_comment = False
                result.append(char)
        elif char == "'" and not in_double_quote:
            in_single_quote = not in_single_quote
            result.append(char)
        elif char == '"' and not in_single_quote:
            in_double_quote = not in_double_quote
            result.append(char)
        elif char == '\\' and i + 1 < len(command) and not in_single_quote:
            result.append(char)
            result.append(command[i + 1])
            i += 1
        elif char == '#' and not in_single_quote and not in_double_quote:
            in_comment = True
        else:
            result.append(char)

        i += 1

    return ''.join(result)


def strip_subshell(command: str) -> str:
    """Strip balanced outer parentheses from subshell commands.

    Examples:
        (cd /tmp && ls) → cd /tmp && ls
        ((nested)) → (nested)
        (unbalanced → (unbalanced (unchanged)
    """
    cmd = command.strip()
    while cmd.startswith('(') and cmd.endswith(')'):
        # Check if parens are balanced
        depth = 0
        balanced = True
        for i, c in enumerate(cmd):
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            # If depth hits 0 before the end, outer parens aren't a pair
            if depth == 0 and i < len(cmd) - 1:
                balanced = False
                break
        if balanced and depth == 0:
            cmd = cmd[1:-1].strip()
        else:
            break
    return cmd


def split_compound_command(command: str) -> list[str]:
    """Split command on &&, ||, ;, |, newline respecting quotes.

    Returns list of individual command segments.
    """
    command = strip_comments(command)
    command = strip_subshell(command)
    segments = []
    current = []
    in_single_quote = False
    in_double_quote = False
    i = 0
    chars = command

    while i < len(chars):
        char = chars[i]

        if char == "'" and not in_double_quote:
            in_single_quote = not in_single_quote
            current.append(char)
        elif char == '"' and not in_single_quote:
            in_double_quote = not in_double_quote
            current.append(char)
        elif char == '\\' and i + 1 < len(chars) and not in_single_quote:
            next_char = chars[i + 1]
            if next_char == '\n':
                # Line continuation - skip both backslash and newline
                i += 1
            else:
                current.append(char)
                current.append(next_char)
                i += 1
        elif not in_single_quote and not in_double_quote:
            if chars[i:i+2] == '&&':
                if current:
                    segments.append(''.join(current).strip())
                    current = []
                i += 1
            elif chars[i:i+2] == '||':
                if current:
                    segments.append(''.join(current).strip())
                    current = []
                i += 1
            elif char == ';' or char == '\n':
                if current:
                    segments.append(''.join(current).strip())
                    current = []
            elif char == '|':
                if current:
                    segments.append(''.join(current).strip())
                    current = []
            else:
                current.append(char)
        else:
            current.append(char)

        i += 1

    if current:
        segments.append(''.join(current).strip())

    return [s for s in segments if s]


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
        - Environment variable stripping
        - Compound command splitting
        - Task runner detection
        - Rule matching

    Returns dict with:
        - action: 'allow', 'deny', or 'ask'
        - reason: Explanation of the decision
        - commands: List of evaluated command segments
    """
    stripped = strip_env_vars(command)
    segments = split_compound_command(stripped)

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
