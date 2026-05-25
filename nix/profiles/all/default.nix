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

    # Preserves `[include] path = .gitconfig.custom` from both source
    # .gitconfigs so user-managed local overrides keep working.
    includes = [ { path = "~/.gitconfig.custom"; } ];

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

  # ~/.gnupg/gpg.conf — preserves the two settings the old commit_signing
  # plugin and the user's manual config had.
  programs.gpg = {
    enable = true;  # also installs pkgs.gnupg into the profile.
    settings = {
      auto-key-retrieve = true;
      no-emit-version   = true;
    };
  };

  # ~/.gnupg/gpg-agent.conf — pinentry is per-OS; cache TTLs match the old
  # plugin's prior behavior (10-minute default, 2-hour max).
  services.gpg-agent = {
    enable = true;
    pinentry.package =
      if pkgs.stdenv.isDarwin then pkgs.pinentry_mac
      else                         pkgs.pinentry-tty;
    defaultCacheTtl = 600;
    maxCacheTtl     = 7200;
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

  # Note: this uses entryBefore [ "checkLinkTargets" ] rather than
  # entryAfter [ "writeBoundary" ] (which the migrateLegacyGitConfig above
  # uses). checkLinkTargets runs *before* writeBoundary and aborts if it
  # finds a real file where a managed symlink should go — and programs.gpg
  # / services.gpg-agent place managed symlinks at ~/.gnupg/gpg.conf and
  # ~/.gnupg/gpg-agent.conf. So the legacy real files must be moved aside
  # before checkLinkTargets runs, not after writeBoundary. The Slice 1 git
  # migration didn't face this because home-manager symlinks at
  # ~/.config/git/config, not ~/.gitconfig — no target-path collision.
  home.activation.migrateLegacyGnupgConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    # One-time migration: home-manager wants to symlink ~/.gnupg/gpg.conf and
    # ~/.gnupg/gpg-agent.conf, but it refuses to overwrite real files. The
    # old commit_signing plugin wrote those as real files; move them aside
    # once so home-manager can take over. Marker lives outside ~/.gnupg/
    # because that dir is GPG-owned mode 0700 and littering it with home-
    # manager bookkeeping feels off.
    if [ ! -e "$HOME/.gnupg.hm-migrated" ]; then
      for f in gpg.conf gpg-agent.conf; do
        if [ -f "$HOME/.gnupg/$f" ] && [ ! -L "$HOME/.gnupg/$f" ]; then
          # Don't use `mv -n` here: it silently no-ops when a .legacy-backup
          # already exists, yet we'd still write the marker below — leaving the
          # real file in place to fail checkLinkTargets forever with no retry.
          # Fail loudly instead so a pre-existing backup is resolved by hand.
          if [ -e "$HOME/.gnupg/$f.legacy-backup" ]; then
            echo "ERROR: $HOME/.gnupg/$f.legacy-backup already exists; refusing to overwrite. Move it aside, then re-run ./apply." >&2
            exit 1
          fi
          run mv "$HOME/.gnupg/$f" "$HOME/.gnupg/$f.legacy-backup"
          echo "Moved legacy ~/.gnupg/$f → ~/.gnupg/$f.legacy-backup (one-time migration)"
        fi
      done
      run touch "$HOME/.gnupg.hm-migrated"
    fi
  '';
}
