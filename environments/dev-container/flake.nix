{
  description = "ianwremmel dotfiles — dev-container environment (alias for agent-interactive)";

  # Kept as a selectable name because homelab's images/dev-base/lib/bootstrap.sh
  # hardcodes DOTFILES_ENVIRONMENT=dev-container. `agent-interactive` holds the
  # content; this flake re-exports its configurations unchanged.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    agent-interactive.url = "github:ianwremmel/dotfiles?dir=environments/agent-interactive";
    agent-interactive.inputs.public.follows = "public";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, agent-interactive, ... }: {
    inherit (agent-interactive) homeConfigurations;
  };
}
