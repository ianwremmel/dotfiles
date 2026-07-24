---
name: claude-remote
description: Start a Remote Control Claude session for one of the ~/projects repos in a detached tmux session, so it can be driven from claude.ai or the mobile app. Invoke as `/claude-remote <project>`.
---

# claude-remote

Launch a second Claude session in `~/projects/$ARGUMENTS` with Remote Control
enabled. It runs detached under tmux, so it outlives this session; it is a
separate session, not a subagent, so nothing here can talk to it afterwards.

1. Take the project name from `$ARGUMENTS`. If empty, list the directories in
   `~/projects` and ask which one.
2. If `~/projects/<project>` is not a directory, say so, list the available
   projects, and stop.
3. If `tmux has-session -t remote-<project>` succeeds, one is already running —
   report it and stop rather than starting a second.
4. Otherwise start it:

       tmux new-session -d -s "remote-<project>" claude-remote <project>

5. Report the Remote Control name (`remote-<project>`, how it appears on
   claude.ai and mobile) and `tmux attach -t remote-<project>` for taking it
   over from a shell here.
