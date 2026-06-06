{ config, lib, pkgs, ... }:
# Shared-optional pairing bundle: the SSH wiring that makes a laptop and its
# remote agents feel like one machine. An environment opts in by adding
# `public.homeModules.pairing` to its `modules` list and setting
# `dotfiles.pairing.mode`. `client` is the laptop side (the launchd mac-agent
# socket handler + a RemoteForward per paired remote); `server` is the agent
# side (the sshd drop-in + the remote-agent shims). Keeping client and server
# in one module keeps the socket path and protocol they share in a single place.
let
  cfg = config.dotfiles.pairing;

  # --- client (macOS) ---
  sock = "${config.home.homeDirectory}/.remote-agent.sock";
  agentBin = "${config.home.homeDirectory}/.local/bin/remote-agent";
  # OAuth callback port-forwarding (the FORWARD verb) targets a single host;
  # use the first paired remote. Multi-remote callback forwarding is out of
  # scope — the socket-based open-link/clipboard/sound verbs work for all
  # remotes since they don't need to know which remote a request came from.
  primaryRemote = if cfg.remotes == [ ] then "" else builtins.head cfg.remotes;
  # One ssh Host block per paired remote: forward the agent's
  # /run/remote-agent.sock back to this machine's local socket.
  remoteSshBlocks = lib.listToAttrs (map
    (h: lib.nameValuePair h {
      ControlMaster = "auto";
      ControlPath = "~/.ssh/cm-%C";
      RemoteForward = "/run/remote-agent.sock ${sock}";
    })
    cfg.remotes);

  # --- server (Linux) ---
  shimSrc = ./remote-agent;
  shimPrefix = toString shimSrc + "/";
  discovered = lib.listToAttrs (map
    (p:
      let name = lib.removePrefix shimPrefix (toString p); in
      lib.nameValuePair "bin/${name}" {
        source = p;
        executable = name != "_remote-agent.sh";
      })
    (builtins.filter
      (p: !(lib.hasInfix "/test/" (toString p)))
      (lib.filesystem.listFilesRecursive shimSrc)));
  aliases = lib.listToAttrs (map
    (n: lib.nameValuePair "bin/${n}" { source = shimSrc + "/open-link"; executable = true; })
    [ "xdg-open" "www-browser" ]);
  sshdDropIn = ''
    # Managed by the dotfiles `pairing` bundle (server mode). Copied into
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
  options.dotfiles.pairing = {
    mode = lib.mkOption {
      type = lib.types.enum [ "off" "client" "server" ];
      default = "off";
      description = "Pairing role: client (laptop), server (agent host), or off.";
    };
    remotes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH host aliases of paired remotes; drives the client RemoteForward blocks.";
    };
  };

  config = lib.mkMerge [
    # CLIENT — macOS launchd socket handler + ssh RemoteForward to the agent.
    (lib.mkIf (cfg.mode == "client" && pkgs.stdenv.isDarwin) {
      home.file.".local/bin/remote-agent" = {
        source = ./mac-agent/agent.sh;
        executable = true;
      };
      launchd.agents.remote-agent = {
        enable = true;
        config = {
          ProgramArguments = [ agentBin ];
          # The handler reads SSH_HOST for the FORWARD verb; point it at the
          # primary paired remote (empty when none are configured).
          EnvironmentVariables.SSH_HOST = primaryRemote;
          # Per-connection socket activation: launchd wires the accepted
          # connection to the handler's stdin/stdout (Wait=false).
          inetdCompatibility.Wait = false;
          Sockets.Listener.SockPathName = sock;
        };
      };
      programs.ssh.settings = remoteSshBlocks;
    })

    # SERVER — sshd drop-in + remote-agent shims (Linux).
    (lib.mkIf (cfg.mode == "server") {
      home.file = lib.mkIf pkgs.stdenv.isLinux (discovered // aliases // {
        ".config/agent/sshd.conf".text = sshdDropIn;
      });
      home.packages = lib.mkIf pkgs.stdenv.isLinux [
        pkgs.netcat-openbsd
        pkgs.iproute2
        pkgs.util-linux
      ];
      home.sessionVariables = lib.mkIf pkgs.stdenv.isLinux { BROWSER = "open-link"; };
      home.activation.installAgentSshdDropIn =
        lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          if [ "$(id -u)" = 0 ] && [ -f "$HOME/.config/agent/sshd.conf" ]; then
            run mkdir -p /etc/ssh/sshd_config.d
            run install -m 0644 "$HOME/.config/agent/sshd.conf" \
              /etc/ssh/sshd_config.d/agent.conf
          fi
        '';
    })
  ];
}
