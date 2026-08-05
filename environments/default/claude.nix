{ ... }:
# Personal-machine Claude Code customizations, layered over the shared
# `homeModules.claude` bundle (folded in via this environment's flake). The
# bundle supplies the ~/.claude content, the base CLAUDE.md, and the
# settings.json seed/merge machinery; here we set only the keys specific to this
# machine. Keys Claude writes itself (permissions.allow, ...) aren't listed and
# are preserved by the merge.
{
  dotfiles.claude.settings = {
    permissions.defaultMode = "auto";
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

  # dispatch needs nothing here: the personal machine is public github.com, so
  # every typed default in core/common/claude/dispatch.nix already matches
  # (solo, shared, Copilot available, Linear), and operatorLogin comes from the
  # generated host.nix via DOTFILES_OPERATOR_LOGIN.
}
