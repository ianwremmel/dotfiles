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
  # One ssh Host block per paired remote: forward the agent's
  # /run/remote-agent.sock back to this machine's local socket. Pairing servers
  # are agent hosts, which log in as root (server mode's sshd drop-in sets
  # PermitRootLogin prohibit-password), so connect as root rather than the
  # laptop's local username.
  remoteSshBlocks = lib.listToAttrs (map
    (h: lib.nameValuePair h {
      User = "root";
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
      description = ''
        ssh Host patterns of paired remotes; drives the client RemoteForward
        blocks. An entry may be a glob (`claude-rc-*`) to cover a fleet whose
        member names aren't known ahead of time.
      '';
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
          # The handler matches the host named in a FORWARD/UNFORWARD request
          # against these patterns before handing it to ssh, and falls back to
          # the first concrete one when a request names no host.
          EnvironmentVariables.REMOTE_AGENT_HOSTS =
            lib.concatStringsSep " " cfg.remotes;
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
