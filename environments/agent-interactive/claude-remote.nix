{ ... }:
{
  # `claude-remote <project> <session>` starts a Remote Control Claude session in
  # one of the cloned repos; the /dotfiles-claude-remote skill launches it under
  # tmux from inside an already-running session. Interactive hosts only — an
  # unattended host has no operator to pick the remote session up.
  home.file.".local/bin/claude-remote" = {
    source = ./bin/claude-remote;
    executable = true;
  };

  dotfiles.claude.extraTrees = [ ./claude ];

  # User settings rather than the agent bundle's managed-settings policy: that
  # policy is shared with the unattended host, which has no operator to pick a
  # remote session up. A repo can still opt out with `false` in its own
  # .claude/settings.json.
  dotfiles.claude.settings.remoteControlAtStartup = true;
}
