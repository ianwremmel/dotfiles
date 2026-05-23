{
  description = "ianwremmel dotfiles — public nix slice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      publicProfiles   = [ "default" "agent" ];
      inherit (nixpkgs) lib;

      # Untracked, plugin-generated per-host values: { username; profile; }.
      # This file reads only `host.username` (for the no-overlay configs below);
      # `host.profile` is consumed by private flakes that may import this one.
      host =
        if builtins.pathExists ./host.nix then import ./host.nix
        else throw "nix/host.nix not found — run ./apply (generates it) or create it: { username = \"<you>\"; profile = \"default\"; }";
    in {
      # Module library for downstream (private) flakes to consume.
      homeModules = {
        base    = ./home.nix;
        default = ./profiles/default/default.nix;
        agent   = ./profiles/agent/default.nix;
      };

      # Helper: build a homeConfiguration with the shared base + caller's extras.
      lib.mkHome = { system, username, modules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit username; };
          modules = [ self.homeModules.base ] ++ modules;
        };

      # Ready-made configs for the no-private-overlay case, one per public profile × system.
      homeConfigurations = builtins.listToAttrs (lib.concatMap (system:
        map (profile: {
          name  = "${profile}@${system}";
          value = self.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [ self.homeModules.${profile} ];
          };
        }) publicProfiles
      ) supportedSystems);
    };
}
