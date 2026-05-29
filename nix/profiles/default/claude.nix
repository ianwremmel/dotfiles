{ pkgs, lib, ... }:
let
  claudeSrc = ./claude;

  jsonFormat = pkgs.formats.json { };

  # Static, Nix-owned Claude Code settings. Claude Code rewrites
  # ~/.claude/settings.json at runtime (approved permissions, etc.), so the
  # file itself can't be a read-only store symlink. These keys are seeded and
  # then re-asserted over the live file on every apply (see seedClaudeSettings);
  # keys Claude writes itself (permissions.allow, ...) aren't listed here and
  # are preserved by the merge.
  settingsDefaults = jsonFormat.generate "claude-settings.json" {
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
    }
    // mapClaudeTree "guides"
    // mapClaudeTree "agents"
    // mapClaudeTree "skills"
    // mapClaudeTree "commands"
    // mapClaudeTree "rules";

  # settings.json is owned by Claude Code at runtime, so it can't be a
  # read-only store symlink. Seed a writable copy on first activation; on
  # subsequent applies recursively merge the Nix-owned defaults over the live
  # file (ours wins on the static keys, Claude's permissions/runtime keys
  # survive).
  home.activation.seedClaudeSettings =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.claude/settings.json"
      run mkdir -p "$HOME/.claude"
      if [ -L "$settings" ] || [ ! -e "$settings" ]; then
        # Prior store symlink or fresh install: drop in a writable copy.
        run rm -f "$settings"
        run install -m 0644 ${settingsDefaults} "$settings"
      elif ${pkgs.jq}/bin/jq -e . "$settings" >/dev/null 2>&1; then
        # Claude owns a valid file: re-assert the static keys without clobbering
        # what Claude wrote (recursive merge; right operand wins on conflicts).
        tmp="$settings.nix-merge"
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${settingsDefaults} > "$tmp"
        run install -m 0644 "$tmp" "$settings"
        run rm -f "$tmp"
      else
        # Unparseable JSON: replace with a clean writable copy.
        run install -m 0644 ${settingsDefaults} "$settings"
      fi
    '';

  home.activation.migrateLegacyClaudeRsync =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for f in \
        "$HOME/.claude/CLAUDE.md" \
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
