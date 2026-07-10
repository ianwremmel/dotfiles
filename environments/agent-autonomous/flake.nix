{
  description = "ianwremmel dotfiles — agent-autonomous environment (agent bundle, unattended)";

  # An unattended agent host: the shared agent bundle and nothing else. Distinct
  # from agent-interactive, which adds a cluster toolchain, repo clones, and a
  # tmux session for a human on the other end of an SSH pipe.
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
        supportedSystems);

      # This environment contributes no darwin module; on macOS it gets the
      # universal base + all system layer only.
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
