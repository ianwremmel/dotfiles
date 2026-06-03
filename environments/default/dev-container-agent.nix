{ config, lib, pkgs, ... }:
let
  sock = "${config.home.homeDirectory}/.dev-container-agent.sock";
  agentBin = "${config.home.homeDirectory}/.local/bin/dev-container-agent";
in
{
  # macOS companion for the homelab dev container: a launchd socket-activated
  # handler that opens URLs, bridges the clipboard, plays sounds, and forwards
  # OAuth callback ports for the pod's remote-agent shims. The matching SSH
  # RemoteForward — which exposes this socket inside the pod as
  # /run/remote-agent.sock — is declared in ./ssh.nix. macOS only (the launchd
  # option exists on all platforms but does nothing off Darwin).
  home.file = lib.mkIf pkgs.stdenv.isDarwin {
    ".local/bin/dev-container-agent" = {
      source = ./mac-agent/agent.sh;
      executable = true;
    };
  };

  launchd.agents.dev-container-agent = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ agentBin ];
      # Per-connection socket activation: launchd wires the accepted connection
      # to the handler's stdin/stdout (Wait=false → no persistent listener).
      inetdCompatibility.Wait = false;
      Sockets.Listener.SockPathName = sock;
    };
  };
}
