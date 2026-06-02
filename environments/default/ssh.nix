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
  # Client config for reaching the homelab dev container, owned here because
  # core manages ~/.ssh/config as a read-only symlink — the mac-agent installer
  # can't append to it. The marker comments mirror the installer's
  # MARK_START/MARK_END so this is recognizably the same block; the installer's
  # own ssh-config step is redundant when this fragment is present. macOS only —
  # the forwarded socket is served by the macOS-only mac-agent launchd job.
  home.file = lib.mkIf pkgs.stdenv.isDarwin {
    ".ssh/config.d/dev-container".text = ''
      # >>> dev-container remote-agent >>>
      Host ${devContainerHost}
          RemoteForward /run/remote-agent.sock ${localSock}
          ControlMaster auto
          ControlPath ~/.ssh/cm-%C
      # <<< dev-container remote-agent <<<
    '';
  };
}
