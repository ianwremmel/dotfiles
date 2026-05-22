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

      # Host-specific values (currently just the username) live in an untracked,
      # plugin-generated nix/host.nix so they never land in git. The `path:`
      # flake reference the plugin uses copies untracked files, so this resolves.
      host =
        if builtins.pathExists ./host.nix
        then import ./host.nix
        else throw "nix/host.nix not found — run ./apply (the nix plugin generates it) or create it: { username = \"<you>\"; }";

      # home.nix derives everything else (home directory, etc.) from the username.
      mkHome = username: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
        extraSpecialArgs = { inherit username; };
      };
    in {
      # Named after the host's username; the plugin builds homeConfigurations.<$(whoami)>,
      # which matches because host.nix is generated from $(whoami).
      homeConfigurations.${host.username} = mkHome host.username;
    };
}
