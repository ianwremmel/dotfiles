{
  description = "ianwremmel dotfiles — agent-autonomous environment (agent bundle, unattended)";

  # An unattended agent host. Identical to agent-interactive except it names no
  # repos to clone — a private environment supplies its own `reposFile`. Linux
  # only, so it emits no darwin configuration.
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
