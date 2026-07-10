{
  description = "ianwremmel dotfiles — agent environment (alias for agent-autonomous)";

  # Kept as a selectable name. `agent-autonomous` holds the content; this flake
  # re-exports its home configurations unchanged (it emits no darwin half —
  # agent hosts are Linux). `agent-autonomous.inputs.public.follows = "public"`
  # makes both build against the same core, which lib/nix overrides to the local
  # checkout.
  inputs = {
    public.url = "github:ianwremmel/dotfiles?dir=core";
    agent-autonomous.url = "github:ianwremmel/dotfiles?dir=environments/agent-autonomous";
    agent-autonomous.inputs.public.follows = "public";
    nixpkgs.follows      = "public/nixpkgs";
    home-manager.follows = "public/home-manager";
    nix-darwin.follows   = "public/nix-darwin";
  };

  outputs = { self, agent-autonomous, ... }: {
    inherit (agent-autonomous) homeConfigurations;
  };
}
