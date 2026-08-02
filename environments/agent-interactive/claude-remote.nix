{ pkgs, ... }:
{
  # `claude-remote <project> <session>` starts a Remote Control Claude session in
  # one of the cloned repos; the /dotfiles-claude-remote skill launches it under
  # tmux from inside an already-running session. Interactive hosts only — an
  # unattended host has no operator to pick the remote session up.

  # claude-remote edits Claude's own config (`$CLAUDE_CONFIG_DIR/.claude.json`,
  # `~/.claude.json` unset) to pre-accept the workspace trust prompt; nothing
  # else in the bundle puts jq on PATH.
  home.packages = [ pkgs.jq ];

  home.file.".local/bin/claude-remote" = {
    source = ./bin/claude-remote;
    executable = true;
  };

  dotfiles.claude.extraTrees = [ ./claude ];
}
