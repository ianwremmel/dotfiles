{
  description = "ianwremmel dotfiles — agent-interactive environment (agent bundle + repos.txt)";

  # Linux-only: an interactive agent host is a container you SSH into. The agent
  # bundle carries everything (cluster tooling, credential restore, cloning,
  # tmux, the claude bundle); this environment only names the repos to clone.
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
              { dotfiles.agent.reposFile = ./repos.txt; }
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        systems);
    };
}
