{
  description = "ianwremmel dotfiles — agent-interactive environment (agent bundle + homelab cluster tooling)";

  # Linux-only: an interactive agent host is a container you SSH into. Layers
  # the shared agent bundle (which carries the claude bundle) with this host's
  # cluster tooling, repo clones, and tmux auto-attach.
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
              ./home.nix
              ./shell-extras.nix
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        systems);
    };
}
