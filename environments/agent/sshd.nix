{ lib, pkgs, ... }:
let
  # sshd drop-in carrying only the settings that differ from the distro default.
  # The consuming host copies it into /etc/ssh/sshd_config.d/ — Debian's stock
  # sshd_config already `Include`s that directory near the top, so these layer
  # over (and win against, by first-match) the base config rather than replacing
  # it. Host keys, the sftp subsystem, and UsePAM come from the base config.
  # Linux only.
  sshdDropIn = ''
    # Managed by the dotfiles `agent` profile. Copied into
    # /etc/ssh/sshd_config.d/ by hosts that opt in.

    # The login user is root; allow key-based root login, never a password.
    PermitRootLogin prohibit-password
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes

    # tmux -CC iTerm2 detection needs LC_TERMINAL forwarded from the client.
    AcceptEnv LANG LC_*

    Banner /etc/issue
    StreamLocalBindUnlink yes
    PrintMotd no
    X11Forwarding no
  '';
in
{
  home.file = lib.mkIf pkgs.stdenv.isLinux {
    ".config/agent/sshd.conf".text = sshdDropIn;
  };
}
