{ lib, pkgs, ... }:
let
  # A complete sshd_config. `sshd -f <file>` replaces the system config
  # wholesale rather than merging, so this must stand on its own. Hosts that
  # run an SSH server opt in by pointing sshd at ~/.config/agent/sshd_config
  # when it exists; other hosts ignore it. Paths assume Debian (the dev
  # container): the host's entrypoint copies the persisted host keys into
  # /etc/ssh, and sftp-server lives under /usr/lib/openssh.
  sshdConfig = ''
    # Managed by the dotfiles `agent` profile. Loaded via `sshd -f` by hosts
    # that opt in.
    HostKey /etc/ssh/ssh_host_ed25519_key
    HostKey /etc/ssh/ssh_host_rsa_key
    HostKey /etc/ssh/ssh_host_ecdsa_key

    # The login user is root; allow key-based root login, never password.
    PermitRootLogin prohibit-password
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    PubkeyAuthentication yes
    AuthorizedKeysFile .ssh/authorized_keys

    # tmux -CC iTerm2 detection needs LC_TERMINAL forwarded from the client.
    AcceptEnv LANG LC_*

    Subsystem sftp /usr/lib/openssh/sftp-server

    Banner /etc/issue
    StreamLocalBindUnlink yes

    UsePAM yes
    PrintMotd no
    X11Forwarding no
  '';
in
{
  # Linux only — the SSH server config is for headless agent hosts, not macOS.
  home.file = lib.mkIf pkgs.stdenv.isLinux {
    ".config/agent/sshd_config".text = sshdConfig;
  };
}
