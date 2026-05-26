{
  description = "ianwremmel dotfiles — public nix slice";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, ... }:
    let
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      darwinSystems    = [ "aarch64-darwin" "x86_64-darwin" ];
      publicProfiles   = [ "default" "agent" ];
      darwinProfiles   = [ "default" ];  # agent is Linux-only; no darwin config
      inherit (nixpkgs) lib;

      # Untracked, plugin-generated per-host values: { username; profile; }.
      host =
        if builtins.pathExists ./host.nix then import ./host.nix
        else throw "nix/host.nix not found — run ./apply (generates it) or create it: { username = \"<you>\"; profile = \"default\"; }";
    in {
      # ---------- home-manager (existing) ----------
      homeModules = {
        base    = ./home.nix;
        all     = ./profiles/all/default.nix;
        default = ./profiles/default/default.nix;
        agent   = ./profiles/agent/default.nix;
      };

      lib.mkHome = { system, username, modules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit username; };
          modules = [ self.homeModules.base self.homeModules.all ] ++ modules;
        };

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

      # ---------- nix-darwin (NEW) ----------
      darwinModules = {
        base    = ./darwin/base.nix;
        default = ./darwin/default/homebrew.nix;
      };

      lib.mkDarwin = { system, modules ? [] }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit (host) username; };
          modules = [ self.darwinModules.base ] ++ modules;
        };

      darwinConfigurations = builtins.listToAttrs (lib.concatMap (system:
        map (profile: {
          name  = "${profile}@${system}";
          value = self.lib.mkDarwin {
            inherit system;
            modules = [ self.darwinModules.${profile} ];
          };
        }) darwinProfiles
      ) darwinSystems);
    };
}
