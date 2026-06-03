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
    # Only that one — locale (LANG/LC_*) comes from the agent profile's session
    # vars, so there's no need to widen the accepted-env surface.
    AcceptEnv LC_TERMINAL

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

  # On a privileged agent host (the dev container activates as root), install the
  # drop-in into /etc/ssh/sshd_config.d/ (the base sshd_config Includes it), so
  # the host doesn't have to. Self-skips when activation isn't root or the file
  # is absent (non-Linux).
  home.activation.installAgentSshdDropIn =
    # After linkGeneration, not just writeBoundary: it copies from the
    # ~/.config/agent/sshd.conf symlink, which linkGeneration creates.
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ "$(id -u)" = 0 ] && [ -f "$HOME/.config/agent/sshd.conf" ]; then
        run mkdir -p /etc/ssh/sshd_config.d
        run install -m 0644 "$HOME/.config/agent/sshd.conf" \
          /etc/ssh/sshd_config.d/agent.conf
      fi
    '';
}
