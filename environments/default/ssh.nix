{ config, lib, pkgs, ... }:
let
  # The pod's Tailscale name (StatefulSet `dev-container` in namespace
  # `dev-container` → `<namespace>-<name>`).
  devContainerHost = "dev-container-dev-container";
  # Where the mac-agent listens locally; the RemoteForward exposes it inside the
  # pod as /run/remote-agent.sock so the pod's open-link/pbcopy/pbpaste reach
  # this machine.
  localSock = "${config.home.homeDirectory}/.dev-container-agent.sock";
in
{
  # Client config for reaching the homelab dev container, merged into the shared
  # programs.ssh config. macOS only — the forwarded socket is served by the
  # macOS-only mac-agent launchd job.
  programs.ssh.settings = lib.mkIf pkgs.stdenv.isDarwin {
    ${devContainerHost} = {
      ControlMaster = "auto";
      ControlPath = "~/.ssh/cm-%C";
      RemoteForward = "/run/remote-agent.sock ${localSock}";
    };
  };
}
