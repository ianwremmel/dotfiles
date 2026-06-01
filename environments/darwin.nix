{ username, ... }: {
  # System state version — pins nix-darwin's behavior. Never bump casually.
  system.stateVersion = 5;

  # nix-darwin-26.05 requires primaryUser for options like homebrew.enable
  # that previously ran as the invoking user. Now all activation runs as root
  # and these options are scoped to primaryUser.
  system.primaryUser = username;

  # Do NOT let nix-darwin manage the Nix installation: Determinate's nix
  # installer (used by the `lib/nix` bootstrap) owns its own daemon
  # and refuses to coexist with nix-darwin's native nix management. With
  # this set to false, nix-darwin still does everything else (homebrew,
  # login shell, Xcode license, system activations); the `nix.*` options
  # that adjust daemon settings or configure Linux builders are just
  # unavailable. See nix-darwin's "Determinate detected, aborting
  # activation" error for context.
  nix.enable = false;

  users.users.${username} = {
    home  = "/Users/${username}";
    shell = "/Users/${username}/.nix-profile/bin/zsh";
  };

  # Touch ID for sudo. nix-darwin's sudo_local module writes
  # /etc/pam.d/sudo_local (the Apple-sanctioned drop-in that survives OS
  # upgrades, unlike editing /etc/pam.d/sudo directly), inserting
  # pam_tid.so so any `sudo` in a terminal pops the native Touch ID
  # dialog and falls back to a password if the fingerprint fails.
  #
  # `reattach` adds pam_reattach.so so the Touch ID prompt also works
  # inside tmux/screen sessions — without it, sudo inside `screen`
  # (see environments/all/home/home-files/screenrc) silently falls back to
  # password entry because the GUI prompt can't attach to the detached
  # session.
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach    = true;
  };
}
