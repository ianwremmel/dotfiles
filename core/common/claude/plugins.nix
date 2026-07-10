# Claude Code plugins every environment gets, as a plain attrset (not a module)
# so it can be spliced into two different shapes of settings JSON:
#
#   - core/common/claude/default.nix folds it into `baseSettings`, which lands
#     in the user's ~/.claude/settings.json.
#   - core/common/agent/claude.nix folds it into the managed-settings policy the
#     agent host installs at /etc/claude-code/managed-settings.json.
#
# A marketplace must be declared before a plugin from it can be enabled; a fresh
# container knows about none of them, so all three are listed explicitly even
# though an interactive machine may already have added them via `/plugin`.
{
  extraKnownMarketplaces = {
    claude-plugins-official.source = {
      source = "github";
      repo = "anthropics/claude-plugins-official";
    };
    openai-codex.source = {
      source = "github";
      repo = "openai/codex-plugin-cc";
    };
    agentic.source = {
      source = "github";
      repo = "ianwremmel/agentic";
    };
  };

  enabledPlugins = {
    "code-review@claude-plugins-official" = true;
    "code-simplifier@claude-plugins-official" = true;
    "typescript-lsp@claude-plugins-official" = true;
    "codex@openai-codex" = true;
    "dispatch@agentic" = true;
  };
}
