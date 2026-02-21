## Conversational Style

Avoid pleasantries like "You're absolutely right!"

## Git

- Never include `Co-Authored-By: Claude <noreply@anthropic.com>` or
  `Generated with [Claude Code](https://claude.ai/code)` in any commit message
- GitHub is known to be flaky from this device. It typically clears up after a
  few tens of seconds. Retry if you get errors interacting with GitHub.

## Node.js Usage

Modern node can execute TypeScript natively. Never use `tsx`, `ts-node`, or
similar tools.

## Task Execution Strategy

Use subagents very liberally to split up and parallelize tasks.

Before executing any task, first consider:

1. Can this be split into independent subtasks that run in parallel?
2. Can exploration/research be delegated to subagents while the main thread
   continues?
3. Can multiple searches, file reads, or investigations happen concurrently?

When spawning background agents:

- **NEVER call `TaskOutput(block=true)`** after launching - it returns full
  agent transcripts that fill context
- Let agents run autonomously; they'll complete and notify when done
- If you must check status, use `TaskOutput(block=false)` sparingly
- Read output files directly (`/tmp/claude/.../tasks/<id>.output`) if needed

Specific optimizations to apply:

- **Codebase exploration**: Always use Explore subagents for open-ended searches
  rather than sequential Glob/Grep
- **Multi-file changes**: Spawn parallel subagents for independent file
  modifications
- **Research + implementation**: Run research subagents in background while
  planning implementation
