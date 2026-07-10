{ lib, pkgs, ... }: {
  programs.git = {
    enable = true;

    # Preserves `[include] path = .gitconfig.custom` from both source
    # .gitconfigs so user-managed local overrides keep working.
    includes = [ { path = "~/.gitconfig.custom"; } ];

    ignores = [
      # Editor temp files
      "*.orig" "*.swp" "*~" ".*.swo" "*.pyc"
      # Archives
      "*.dmg" "*.gz" "*.iso" "*.rar" "*.tar" "*.zip"
      # Logs and databases
      "*.log" "*.sql" "*.sqlite"
      # OS generated files
      ".DS_Store" ".DS_Store?" ".Spotlight-V100" ".Trashes" "._*" "Icon?" "Thumbs.db" "Desktop.ini"
      # Eclipse/Aptana
      ".settings" ".project"
      # Claude Code local settings (never commit per-project local overrides)
      "**/.claude/settings.local.json"
    ];

    # `settings` replaces the older `aliases` + `extraConfig` options
    # (renamed in home-manager; the old names emit a deprecation warning).
    # `settings.alias` is the alias subsection; the other top-level attrs
    # map to git config sections of the same name.
    settings = {
      alias = {
        autosquash = "!GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash";
        fixup      = "commit --fixup";
        pfl        = "push --force-with-lease";
      };

      branch = {
        sort = "-committerdate";
        main.rebase = true;
        master.rebase = true;
      };

      color = {
        ui = "auto";
        branch = { current = "yellow reverse"; local = "yellow"; remote = "green"; };
        diff   = { frag = "magenta bold"; meta = "yellow bold"; new = "green bold"; old = "red bold"; };
        status = { added = "yellow"; changed = "green"; untracked = "cyan"; };
      };

      core = {
        attributesfile    = "~/.gitattributes";
        precomposeunicode = false;
        trustctime        = false;
        whitespace        = "space-before-tab,indent-with-non-tab,trailing-space";
      };

      diff = {
        algorithm       = "histogram";
        indentHeuristic = true;
        renames         = "copies";
      };

      init.defaultBranch = "main";

      # opendiff ships with Xcode and only exists on macOS; gate it so
      # `git mergetool` on Linux doesn't try to invoke a missing tool.
      merge = {
        conflictstyle = "zdiff3";
        keepbackup    = false;
        log           = true;
      } // lib.optionalAttrs pkgs.stdenv.isDarwin {
        tool = "opendiff";
      };

      # `current` resolves the push destination from the branch's own name and
      # ignores its upstream, so a branch cut from `master` cannot push to
      # `master`. `autoSetupRemote` creates the same-named remote branch on
      # first push, so a bare `git push` still works on a new branch.
      push = {
        default         = "current";
        autoSetupRemote = true;
      };

      rebase = {
        autoStash  = true;
        updateRefs = true;
      };

      rerere = {
        autoupdate = true;
        enabled    = 1;
      };
    };
  };

  home.activation.migrateLegacyGitConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # One-time migration from Slice 1: move pre-migration ~/.gitconfig aside
    # so it stops shadowing the home-manager-managed ~/.config/git/config.
    # The marker file makes this idempotent — necessary because before this
    # slice, the commit_signing plugin ran *before* nix on macOS and would
    # recreate ~/.gitconfig with signing fields, which without the marker
    # would cause the guard to re-move the file every apply.
    # commit_signing is now retired, but the marker guard remains so
    # machines that already migrated in Slice 1 don't re-trigger the
    # backup logic on subsequent applies.
    if [ -f "$HOME/.gitconfig" ] \
         && [ ! -L "$HOME/.gitconfig" ] \
         && [ ! -e "$HOME/.gitconfig.hm-migrated" ]; then
      run mv "$HOME/.gitconfig" "$HOME/.gitconfig.legacy-backup"
      # Use bare echo (not verboseEcho) so this one-time event is visible in
      # a normal ./apply run without requiring DOTFILES_DEBUG / $VERBOSE.
      echo "Moved legacy ~/.gitconfig → ~/.gitconfig.legacy-backup (one-time migration)"
    fi

    # Record that the one-time migration has run — even on a fresh machine with
    # no legacy ~/.gitconfig to move — so a later activation never re-triggers
    # the backup logic.
    run touch "$HOME/.gitconfig.hm-migrated"

    # NOTE: Slice 1's always-on `touch ~/.gitconfig` clause is intentionally
    # gone in this slice — commit_signing (its only consumer) is retired, so
    # nothing else writes to ~/.gitconfig anymore.
  '';
}
