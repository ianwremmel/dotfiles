{ config, lib, ... }:
# Typed `userConfig` for the dispatch@agentic plugin, rendered into
# `dotfiles.claude.settings` as the `pluginConfigs` block the plugin reads.
#
# Why a typed submodule rather than each profile writing the raw attrset: the
# plugin's values are per-profile (the forge, the tracker, which account the
# agent posts as), but `dotfiles.claude.settings` is typed `anything`, so a raw
# block could omit `operator_login`, misspell a key, or supply an invalid enum
# and still build. Because the bundle's activation merges Nix over the live
# settings.json and jq cannot express deletion, a profile that silently declares
# nothing leaves whatever wrong value was there before. The options below turn
# every one of those into an eval error instead.
let
  cfg = config.dotfiles.claude.dispatch;
in
{
  options.dotfiles.claude.dispatch = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to render dispatch's userConfig at all. True by default because
        ./plugins.nix enables dispatch@agentic for every profile. A profile that
        turns the plugin off sets this false as well, which also drops the
        `operatorLogin` requirement — an unused login should not be mandatory.

        This is a separate flag rather than a read of
        `dotfiles.claude.settings.enabledPlugins` because this module *defines*
        `dotfiles.claude.settings`, and reading the option it contributes to
        risks a module-system cycle.
      '';
    };

    operatorLogin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ianwremmel";
      description = ''
        Forge login of the operator directing this agent. The plugin marks this
        required and ships no default, so it must be set on every profile — and
        it is forge-specific: a github.com login is wrong on a GitHub Enterprise
        host.
      '';
    };

    operatorMode = lib.mkOption {
      type = lib.types.enum [ "solo" "team" ];
      default = "solo";
      description = ''
        `team` adds a private review stage in draft (operator only) before
        clearing draft for public review. `solo` clears draft after Copilot and
        makes the operator the public reviewer.
      '';
    };

    credentialMode = lib.mkOption {
      type = lib.types.enum [ "shared" "dedicated" ];
      default = "shared";
      description = ''
        `shared`: the agent uses the operator's credentials, so its posts are
        sparkle-wrapped and review requests cannot target the operator.
        `dedicated`: the agent has its own account.
      '';
    };

    copilotAvailable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether Copilot review works on this forge. False skips the Copilot
        phase and goes straight to human review.
      '';
    };

    tracker = lib.mkOption {
      type = lib.types.str;
      default = "linear";
      description = ''
        Default work-item tracker, named by the id of its adapter skill
        (`tracker-adapter-<id>`). Only `linear` ships an adapter; anything else
        is driven best-effort through its native MCP server.
      '';
    };

    worktreeBase = lib.mkOption {
      type = lib.types.str;
      default = "~/projects/worktrees";
      description = ''
        Root for per-PR worktrees (`<base>/<owner>/<repo>/<branch>`). Kept
        `~`-relative because the agent host renders the same value into a
        system-wide policy read by whichever user runs Claude. Nothing in the
        plugin resolves this — it is interpolated into prompt text for a shell
        to expand — so a value that only expands at word start is a known
        sharp edge; prefer an absolute path if a profile ever needs one.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.operatorLogin != null;
      message = ''
        dotfiles.claude.dispatch.operatorLogin is unset, but the Claude bundle
        enables dispatch@agentic, whose `operator_login` is required and has no
        default. Set it on this profile, or set
        dotfiles.claude.dispatch.enable = false if this profile does not use
        dispatch.
      '';
    }];

    dotfiles.claude.settings.pluginConfigs."dispatch@agentic".options = {
      operator_login = cfg.operatorLogin;
      operator_mode = cfg.operatorMode;
      credential_mode = cfg.credentialMode;
      copilot_available = cfg.copilotAvailable;
      tracker = cfg.tracker;
      worktree_base = cfg.worktreeBase;
    };
  };
}
