{
  description = "ianwremmel dotfiles — core library flake";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, ... }:
    {
      # Shared home-manager layers. `base` is infrastructure (username,
      # stateVersion, allowUnfree); `all` is the content every machine gets.
      # Bundles under `common/` are shared-but-optional: an environment folds
      # one into its own `modules` list to opt in (see `core/common/claude`).
      homeModules = {
        base = ./home.nix;
        all  = ./all/home/default.nix;

        agent   = ./common/agent;
        claude  = ./common/claude;
        pairing = ./common/pairing;
      };

      # Shared nix-darwin layers. `base` is infrastructure (state version,
      # primaryUser, login user, Touch ID); `all` is the universal system
      # content (system PATH, login shell, Xcode license, base homebrew).
      darwinModules = {
        base = ./darwin.nix;
        all  = ./all/darwin/default.nix;
      };

      # Build a home-manager configuration from the shared layers plus any
      # environment-supplied modules.
      #
      # `host` is passed as a module arg alongside `username` so a shared module
      # can read host-specific values lib/nix generates (currently
      # `operatorLogin`). Read here rather than added to this function's
      # signature so no environment flake — including the private ones, which
      # this repo cannot change — has to be updated to forward it. `or { }`
      # keeps the library importable when host.nix is absent, e.g. a fresh
      # clone inspected before the first ./apply.
      lib.mkHome = { system, username, modules ? [] }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = {
            inherit username;
            host = if builtins.pathExists ./host.nix then import ./host.nix else { };
          };
          modules = [ self.homeModules.base self.homeModules.all ] ++ modules;
        };

      # Build a nix-darwin configuration from the shared layers plus any
      # environment-supplied modules.
      lib.mkDarwin = { system, username, modules ? [] }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit username; };
          modules = [ self.darwinModules.base self.darwinModules.all ] ++ modules;
        };
    };
}
