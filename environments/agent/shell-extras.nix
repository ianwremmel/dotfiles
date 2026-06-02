{ lib, ... }:
let
  # Auto-attach interactive logins to a `main` tmux session so any agent the
  # user launches lives inside a save-able pane and survives a dropped
  # connection. Skipped when already inside tmux, with no controlling TTY (e.g.
  # `ssh host tofu apply`, scp, git push), when NO_TMUX=1, or when tmux is
  # absent. With iTerm2 (LC_TERMINAL forwarded over SSH) use `-CC` so each tmux
  # window renders as a native iTerm2 window; -CC shares the same server, so
  # reconnect-to-existing-session works the same as the plain path.
  tmuxAutoAttach = ''
    if [ -z "''${TMUX:-}" ] && [ -t 1 ] && [ "''${NO_TMUX:-}" != 1 ] && command -v tmux >/dev/null 2>&1; then
      if [ "''${LC_TERMINAL:-}" = "iTerm2" ]; then
        exec tmux -CC new-session -A -s main
      else
        exec tmux new-session -A -s main
      fi
    fi
  '';
in
{
  # Appended after core/all's shell init (mkAfter) so the exec — which replaces
  # the shell — runs only once everything else has been set up.
  programs.bash.bashrcExtra = lib.mkAfter tmuxAutoAttach;
  programs.zsh.initContent = lib.mkAfter tmuxAutoAttach;
}
