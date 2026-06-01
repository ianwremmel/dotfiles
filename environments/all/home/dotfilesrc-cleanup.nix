{ lib, ... }: {
  # Scrub the now-vestigial FIRSTRUN_APPLIED key from ~/.dotfilesrc.
  # The framework/firstrun bash plugin (which set this key) was removed in
  # the same commit that introduces this file. Idempotent: if the key is
  # already absent, the activation is a no-op. No backup file is written.
  home.activation.removeFirstrunAppliedKey =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -f "$HOME/.dotfilesrc" ] && /usr/bin/grep -q '^FIRSTRUN_APPLIED=' "$HOME/.dotfilesrc"; then
        # Use a unique temp file (not a fixed ~/.dotfilesrc.tmp) so we never
        # clobber a pre-existing stray file or race a concurrent activation.
        # It lives in $HOME so the final `mv` is an atomic same-filesystem rename.
        tmp="$(/usr/bin/mktemp "$HOME/.dotfilesrc.XXXXXX")"
        /usr/bin/grep -v '^FIRSTRUN_APPLIED=' "$HOME/.dotfilesrc" > "$tmp"
        /bin/chmod 0600 "$tmp"
        /bin/mv "$tmp" "$HOME/.dotfilesrc"
      fi
    '';
}
