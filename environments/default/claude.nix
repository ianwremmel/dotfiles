{ ... }:
# Personal-machine Claude Code customizations, layered over the shared
# `homeModules.claude` bundle (folded in via this environment's flake). The
# bundle supplies the ~/.claude content, the base CLAUDE.md, and the
# settings.json seed/merge machinery; here we set only the keys specific to this
# machine. Keys Claude writes itself (permissions.allow, ...) aren't listed and
# are preserved by the merge.
{
  dotfiles.claude.settings = {
    permissions.defaultMode = "plan";
    hooks = {
      Stop = [
        { hooks = [{ type = "command"; command = "afplay -v 0.40 /System/Library/Sounds/Morse.aiff"; }]; }
      ];
      Notification = [
        { hooks = [{ type = "command"; command = "afplay -v 0.35 /System/Library/Sounds/Ping.aiff"; }]; }
      ];
    };
    alwaysThinkingEnabled = true;
    sandbox = {
      autoAllowBashIfSandboxed = true;
      enabled = true;
      excludedCommands = [ "git" ];
    };
  };
}
