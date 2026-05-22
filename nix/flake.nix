{
  description = "ianwremmel dotfiles — nix-managed slice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, home-manager, ... }:
    let
      system = "aarch64-darwin"; # macOS arm64; add other systems when this goes cross-platform
      pkgs = nixpkgs.legacyPackages.${system};

      # The single place a user is declared. home.nix derives everything else
      # (home directory, etc.) from the username passed here.
      mkHome = username: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
        extraSpecialArgs = { inherit username; };
      };
    in {
      # The nix plugin selects homeConfigurations.<$(whoami)>, so the attribute
      # name and the username must match. Add machines/users with one more line.
      homeConfigurations.ian = mkHome "ian";
    };
}
