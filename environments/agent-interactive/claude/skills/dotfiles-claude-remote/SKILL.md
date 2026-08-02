---
name: dotfiles-claude-remote
description: Start a Remote Control Claude session for one of the ~/projects repos in a detached tmux session, so it can be driven from claude.ai or the mobile app. Invoke as `/dotfiles-claude-remote <project> <session>`.
---

# dotfiles-claude-remote

Launch a second Claude session in `~/projects/<project>` with Remote Control
enabled. It runs detached under tmux, so it outlives this session, and it is a
separate session rather than a subagent of this one.

1. `$ARGUMENTS` is `<project> <session>` — both are required. The session
   identifier is what distinguishes concurrent sessions on the same repo (e.g.
   `review`, `dev-container-bug`). Ask for whichever is missing, listing the
   directories in `~/projects` when the project is the missing one.
2. Both may contain only letters, digits, `_` and `-` — they become one tmux
   session name, which can hold neither `.` nor `:`. Reject a bad identifier
   here and ask for another; `claude-remote` also rejects it, but only after
   `tmux new-session` has already returned, which reads as a session that
   started and vanished.
3. If `~/projects/<project>` is not a directory, say so, list the available
   projects, and stop.
4. If `tmux has-session -t "=remote-<project>-<session>"` succeeds, one is
   already running — report it and stop rather than starting a second. Keep the
   leading `=`: without it tmux matches a target by prefix, so the check also
   fires for an unrelated `remote-<project>-<session>-<something>`.
5. Otherwise start it:

       tmux new-session -d -s "remote-<project>-<session>" claude-remote <project> <session>

6. Report the Remote Control name (`remote-<project>-<session>`, how it appears
   on claude.ai and mobile) and `tmux attach -t "=remote-<project>-<session>"`
   for taking it over from a shell here.
