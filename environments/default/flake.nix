{
  description = "ianwremmel dotfiles — default environment";

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
      # Personal-machine home configs (Claude config, personal CLI tools,
      # terminal fonts, git identity + signing) layered over the shared base.
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [ ./home.nix public.homeModules.claude ];
          };
        })
        supportedSystems);

      # macOS system config adds the personal casks/mas/brews on top of the
      # shared base+all darwin layers. Darwin is platform-gated: only the
      # darwin systems get an output.
      darwinConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkDarwin {
            inherit system;
            inherit (host) username;
            modules = [ ./darwin.nix ];
          };
        })
        darwinSystems);
    };
}
