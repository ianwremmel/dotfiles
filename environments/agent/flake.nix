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
      # Lean home config: the agent layer adds nothing beyond the shared base.
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [ ./home.nix ];
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
