---
name: dotfiles-claude-remote
description: Start a Remote Control Claude session for one of the ~/projects repos in a detached tmux session, so it can be driven from claude.ai or the mobile app. Invoke as `/dotfiles-claude-remote <project> <session>`.
---

# dotfiles-claude-remote

Launch a second Claude session in `~/projects/<project>` with Remote Control
enabled. It runs detached under tmux, so it outlives this session; it is a
separate session, not a subagent, so nothing here can talk to it afterwards.

1. `$ARGUMENTS` is `<project> <session>` — both are required. The session
   identifier is what distinguishes concurrent sessions on the same repo (e.g.
   `review`, `dev-container-bug`); it may contain only letters, digits, `_` and
   `-`. Ask for whichever is missing, listing the directories in `~/projects`
   when the project is the missing one.
2. If `~/projects/<project>` is not a directory, say so, list the available
   projects, and stop.
3. If `tmux has-session -t remote-<project>-<session>` succeeds, one is already
   running — report it and stop rather than starting a second.
4. Otherwise start it:

       tmux new-session -d -s "remote-<project>-<session>" claude-remote <project> <session>

   `claude-remote` accepts the workspace trust prompt on its own for a project
   Claude has never run in, since nothing detached can answer it.

5. Report the Remote Control name (`remote-<project>-<session>`, how it appears
   on claude.ai and mobile) and `tmux attach -t remote-<project>-<session>` for
   taking it over from a shell here.
