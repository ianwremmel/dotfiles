{
  description = "ianwremmel dotfiles — dev-container environment (agent profile + homelab cluster tooling)";

  # Linux-only (the homelab dev container). Inherits the generic `agent`
  # profile. `agent.inputs.public.follows = "public"` makes the agent layer
  # build against the same core. lib/nix overrides BOTH `public` and `agent` to
  # the local checkout at build time (see its --override-input flags), so the
  # github refs here are placeholders that never fetch during ./apply.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    agent.url = "github:ianwremmel/dotfiles?dir=environments/agent";
    agent.inputs.public.follows = "public";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, public, agent, ... }:
    let
      host = import (public + "/host.nix");
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in {
      # Agent profile + this container's cluster tooling, opting into the
      # pairing bundle as a server (the agent home module can't carry bundles
      # across the flake boundary, so add them here explicitly).
      homeConfigurations = builtins.listToAttrs (map
        (system: {
          name = system;
          value = public.lib.mkHome {
            inherit system;
            inherit (host) username;
            modules = [
              agent.homeModules.agent
              ./dev-container.nix
              public.homeModules.pairing
              { dotfiles.pairing.mode = "server"; }
            ];
          };
        })
        systems);
    };
}
