{ lib, pkgs, ... }: {
  # `all` is composed into every config by `lib.mkHome`, regardless of which
  # profile is active or whether a private flake overlays on top — anything
  # *every* machine should get goes here.
  programs.bat = {
    enable = true;          # installs bat (the package half of the slice)
    config.theme = "ansi";  # writes ~/.config/bat/config (the dotfile half)
  };

  programs.git = {
    enable = true;

    aliases = {
      autosquash = "!GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash";
      fixup      = "commit --fixup";
      pfl        = "push --force-with-lease";
    };

    # Preserves `[include] path = .gitconfig.custom` from both source
    # .gitconfigs so user-managed local overrides keep working.
    includes = [ { path = "~/.gitconfig.custom"; } ];

    extraConfig = {
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
        excludesfile      = "~/.gitignore";
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

      push.default = "upstream";

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
    # One-time migration: move pre-migration ~/.gitconfig aside so it stops
    # shadowing the home-manager-managed ~/.config/git/config. The marker
    # file makes this idempotent — necessary because the commit_signing
    # plugin runs *before* nix on macOS (alphabetical plugin order) and
    # recreates ~/.gitconfig with signing fields via `git config --global`,
    # so the guard would otherwise re-move the file every apply.
    if [ -f "$HOME/.gitconfig" ] \
         && [ ! -L "$HOME/.gitconfig" ] \
         && [ ! -e "$HOME/.gitconfig.hm-migrated" ]; then
      run mv "$HOME/.gitconfig" "$HOME/.gitconfig.legacy-backup"
      verboseEcho "Moved legacy ~/.gitconfig → ~/.gitconfig.legacy-backup (one-time migration)"
    fi

    # Record that the one-time migration has run — even on a fresh machine with
    # no legacy ~/.gitconfig to move — so the empty seed file created below is
    # never mistaken for legacy config and "migrated" on the next activation.
    run touch "$HOME/.gitconfig.hm-migrated"

    # Always ensure ~/.gitconfig exists as a writable empty real file. Git's
    # `--global` config writes prefer ~/.gitconfig when it exists, falling
    # back to $XDG_CONFIG_HOME/git/config otherwise — but the XDG file is
    # home-manager-managed (a read-only symlink into /nix/store), so any
    # `git config --global` call (commit_signing, ad-hoc user invocations)
    # would fail without this seed file.
    if [ ! -e "$HOME/.gitconfig" ]; then
      run touch "$HOME/.gitconfig"
    fi
  '';
}
