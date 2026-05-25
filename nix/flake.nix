{
  description = "ianwremmel dotfiles — public nix slice";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
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
      # `base` is infrastructure; `all` is always-included shared content;
      # `default`/`agent` are selectable profiles. mkHome always composes
      # base + all + the caller's chosen profile modules.
      homeModules = {
        base    = ./home.nix;
        all     = ./profiles/all/default.nix;
        default = ./profiles/default/default.nix;
        agent   = ./profiles/agent/default.nix;
      };

      # Helper: build a homeConfiguration with the shared base + always-on
      # `all` layer + caller's extras (profile-specific and/or private).
      lib.mkHome = { system, username, modules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit username; };
          modules = [ self.homeModules.base self.homeModules.all ] ++ modules;
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
