{
  description = "ianwremmel dotfiles — agent environment";

  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, public, ... }:
    let
      host = import (public + "/host.nix");
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      darwinSystems    = [ "aarch64-darwin" "x86_64-darwin" ];
    in {
      # The agent home module, exposed so consumers (e.g. the homelab dev
      # container) can fold it into their own home config alongside their own
      # modules — `public.lib.mkHome { modules = [ agent.homeModules.agent ... ]; }`.
      homeModules.agent = ./home.nix;

      # Home config layering the agent module over the shared base.
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              ./home.nix
              public.homeModules.claude
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        supportedSystems);

      # macOS system config is the shared base+all darwin layers only — the
      # agent environment contributes no darwin module. Darwin is
      # platform-gated: only the darwin systems get an output.
      darwinConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkDarwin {
            inherit system;
            inherit (host) username;
            modules = [ ];
          };
        })
        darwinSystems);
    };
}
