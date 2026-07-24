{ ... }:
{
  # `claude-remote <project>` starts a Remote Control Claude session in one of
  # the cloned repos; the /claude-remote skill launches it under tmux from
  # inside an already-running session. Interactive hosts only — an unattended
  # host has no operator to pick the remote session up.
  home.file.".local/bin/claude-remote" = {
    source = ./bin/claude-remote;
    executable = true;
  };

  dotfiles.claude.extraTrees = [ ./claude ];
}
