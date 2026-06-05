{ config, pkgs, lib, ... }:
# Shared-optional Claude Code bundle. An environment opts in by adding
# `public.homeModules.claude` to the `modules` list it passes to `mkHome`, then
# customizes through `dotfiles.claude.*`. The machinery here (the ~/.claude tree
# walker and the settings.json seed/merge) is environment-agnostic; the content
# in ./files and the base ~/.claude/CLAUDE.md are shared across every profile
# that imports the bundle.
let
  cfg = config.dotfiles.claude;
  jsonFormat = pkgs.formats.json { };

  # Map every regular file under a source tree to a home.file entry rooted at
  # ~/.claude/<relpath>. Managing individual files (not whole directories) keeps
  # ~/.claude/<subdir>/ writable and never shadows live Claude Code content
  # (e.g. an interactively-created command). `.gitkeep` placeholders are skipped.
  mapTree = srcDir:
    let
      prefix = toString srcDir + "/";
      files = lib.filesystem.listFilesRecursive srcDir;
      keep = builtins.filter (p: baseNameOf (toString p) != ".gitkeep") files;
      mkEntry = p:
        lib.nameValuePair
          ".claude/${lib.removePrefix prefix (toString p)}"
          { source = p; };
    in
    lib.listToAttrs (map mkEntry keep);

  # Bundle-shipped content. mkDefault so another module can override a specific
  # path if it ever needs to.
  baseTree = lib.mapAttrs (_: v: { source = lib.mkDefault v.source; }) (mapTree ./files);

  # Profile-supplied trees, mapped the same way. A profile file at the same
  # ~/.claude path as a bundle file wins (extraTree replaces the baseTree key).
  extraTree = lib.foldl' (acc: t: acc // mapTree t) { } cfg.extraTrees;

  # Keys every profile should have; per-profile keys come from cfg.settings and
  # win on conflict. Empty today — kept so universal defaults have a home.
  baseSettings = { };
  settingsFile =
    jsonFormat.generate "claude-settings.json" (lib.recursiveUpdate baseSettings cfg.settings);
in
{
  options.dotfiles.claude = {
    settings = lib.mkOption {
      type = lib.types.anything;
      default = { };
      description = ''
        Nix-owned ~/.claude/settings.json keys. Seeded and re-asserted over the
        live file on every apply (keys Claude writes itself, like
        permissions.allow, are preserved). Because the type is `anything`,
        multiple modules each setting this deep-merge.
      '';
    };

    extraTrees = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Extra directories mapped 1:1 into ~/.claude/ alongside the bundle's own
        content. A file here at the same path as a bundle file wins.
      '';
    };

    claudeMd = lib.mkOption {
      type = lib.types.path;
      default = ./CLAUDE_DOT_MD.md;
      description = ''
        Source for ~/.claude/CLAUDE.md. Defaults to the bundle's shared base; a
        profile replaces it by setting this option (an option default is the
        lowest priority, so the assignment wins).
      '';
    };
  };

  config = {
    home.file =
      baseTree
      // extraTree
      // { ".claude/CLAUDE.md".source = cfg.claudeMd; };

    # settings.json is owned by Claude Code at runtime, so it can't be a
    # read-only store symlink. Seed a writable copy on first activation; on
    # subsequent applies recursively merge the Nix-owned keys over the live file
    # (ours wins on the declared keys, Claude's permissions/runtime keys survive).
    home.activation.seedClaudeSettings =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings="$HOME/.claude/settings.json"
        run mkdir -p "$HOME/.claude"
        if [ -L "$settings" ] || [ ! -e "$settings" ]; then
          # Prior store symlink or fresh install: drop in a writable copy.
          run rm -f "$settings"
          run install -m 0644 ${settingsFile} "$settings"
        elif ${pkgs.jq}/bin/jq -e . "$settings" >/dev/null 2>&1; then
          # Claude owns a valid file: re-assert the declared keys without
          # clobbering what Claude wrote (recursive merge; right operand wins).
          # The merge writes a temp file via redirection, which `run`/$DRY_RUN_CMD
          # can't gate (the shell opens the redirect before the command runs), so
          # skip the whole write under `home-manager switch -n`.
          if [ -z "$DRY_RUN_CMD" ]; then
            tmp="$settings.nix-merge"
            ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${settingsFile} > "$tmp"
            install -m 0644 "$tmp" "$settings"
            rm -f "$tmp"
          else
            echo "would merge ${settingsFile} into $settings"
          fi
        else
          # Unparseable JSON: replace with a clean writable copy.
          run install -m 0644 ${settingsFile} "$settings"
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
  };
}
