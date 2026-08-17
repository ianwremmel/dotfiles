{
  description = "ianwremmel dotfiles — agent-interactive environment (agent bundle, SSH-in host)";

  # Linux-only: an interactive agent host is a container you SSH into. The agent
  # bundle carries the tooling, tmux, and the claude bundle. Cloning, git
  # identity, and the bot-key ssh block belong to whatever runs the host.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in {
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              public.homeModules.agent
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        systems);
    };
}
