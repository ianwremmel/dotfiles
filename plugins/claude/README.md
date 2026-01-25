# Claude Plugin

Plugin for Claude Code CLI configuration including Bash command validation hooks.

## Features

- **PreToolUse Hook**: Validates Bash commands against configurable rules before execution
- **PostToolUse Hook**: Offers to add allow rules for manually approved commands
- **Task Runner Detection**: Recognizes `npx`, `npm run`, `yarn dlx`, etc. and evaluates the underlying command
- **Compound Command Support**: Handles `&&`, `||`, `;`, and `|` operators

## Configuration

Edit `~/.claude/hooks/pre-tool-use/bash.yml` to customize rules.

### Structure

```yaml
logging:
  enabled: true
  path: "$HOME/.claude/logs/pre-tool-use/bash.log"

taskRunners:
  simple: [npx, uvx, bunx]
  nested:
    npm: [run, exec]
    yarn: [run, dlx]

commands:
  git:
    action: allow
    rules:
      - switches: ["--force"]
        action: deny
    subcommands:
      push:
        action: allow
        rules:
          - switches: ["--force-with-lease"]
            action: allow
          - switches: ["--force"]
            action: deny
```

### Actions

- `allow`: Command executes without prompting
- `deny`: Command is blocked with explanation
- `ask`: User must approve (default for unknown commands)

### Rule Matching

1. Environment variables are stripped (`DEBUG=1 npm run` → `npm run`)
2. Compound commands are split and each segment evaluated
3. Task runners are detected and the effective command is evaluated
4. First matching rule wins

## Testing

```bash
# Run all tests
pytest plugins/claude/hooks/ -v

# Run specific test file
pytest plugins/claude/hooks/pre-tool-use/bash_test.py -v
```

## Files

Plugin source (`plugins/claude/`):
- `claude` - Plugin script
- `Brewfile` - Dependencies
- `hooks/lib/bash_common.py` - Shared library
- `hooks/pre-tool-use/bash` - PreToolUse hook
- `hooks/pre-tool-use/bash.yml` - Configuration
- `hooks/post-tool-use/bash` - PostToolUse hook

Installed to (`~/.claude/hooks/`):
- `pre-tool-use/bash` - Hook script
- `pre-tool-use/bash.yml` - Configuration
- `post-tool-use/bash` - Hook script
- `lib/bash_common.py` - Shared library

## Logs

When logging is enabled, decisions are logged to `~/.claude/logs/pre-tool-use/bash.log`:

```json
{"timestamp": "2024-01-15T10:30:00", "command": "git push --force", "action": "deny", "reason": "..."}
```
