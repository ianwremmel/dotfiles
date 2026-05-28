{ pkgs, lib, ... }:
let
  claudeSrc = ./claude;

  jsonFormat = pkgs.formats.json { };

  # Map every regular file under ./claude/<subdir>/ to a home.file entry
  # rooted at ~/.claude/<subdir>/<relpath>. Managing individual files (not
  # whole directories) keeps ~/.claude/<subdir>/ writable and never shadows
  # live Claude Code content (e.g. an interactively-created command). To add
  # a new agent/skill/command/rule, drop a file in the matching subdir and
  # run ./apply. `.gitkeep` placeholders are filtered out.
  mapClaudeTree = subdir:
    let
      srcDir = claudeSrc + "/${subdir}";
      prefix = toString srcDir + "/";
      files = lib.filesystem.listFilesRecursive srcDir;
      keep = builtins.filter (p: baseNameOf (toString p) != ".gitkeep") files;
      mkEntry = p:
        lib.nameValuePair
          ".claude/${subdir}/${lib.removePrefix prefix (toString p)}"
          { source = p; };
    in
    lib.listToAttrs (map mkEntry keep);
in
{
  home.file =
    {
      ".claude/CLAUDE.md".source = claudeSrc + "/CLAUDE_DOT_MD.md";

      ".claude/settings.json".source = jsonFormat.generate "claude-settings.json" {
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
    // mapClaudeTree "guides"
    // mapClaudeTree "agents"
    // mapClaudeTree "skills"
    // mapClaudeTree "commands"
    // mapClaudeTree "rules";

  home.activation.migrateLegacyClaudeRsync =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for f in \
        "$HOME/.claude/CLAUDE.md" \
        "$HOME/.claude/settings.json" \
        "$HOME/.claude/guides/conventional-commits.md" \
        "$HOME/.claude/guides/standard-readme-spec.md"; do
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          # Use home-manager's `run` (honors dry-run) instead of /bin/mv, and
          # `-n` so a leftover *.legacy-backup from a partial prior migration
          # isn't clobbered (a no-op then surfaces loudly at checkLinkTargets).
          run mv -n "$f" "$f.legacy-backup"
        fi
      done
    '';
}
