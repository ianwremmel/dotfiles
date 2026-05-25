{ lib, pkgs, ... }: {
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

  # Note: this uses entryBefore [ "checkLinkTargets" ] rather than
  # entryAfter [ "writeBoundary" ] (which the migrateLegacyGitConfig in
  # git.nix uses). checkLinkTargets runs *before* writeBoundary and aborts
  # if it finds a real file where a managed symlink should go — and
  # programs.gpg / services.gpg-agent place managed symlinks at
  # ~/.gnupg/gpg.conf and ~/.gnupg/gpg-agent.conf. So the legacy real files
  # must be moved aside before checkLinkTargets runs, not after
  # writeBoundary. The Slice 1 git migration didn't face this because
  # home-manager symlinks at ~/.config/git/config, not ~/.gitconfig — no
  # target-path collision.
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
