{ ... }: {
  # The `agent` environment is the reusable base for autonomous-agent hosts:
  # the tooling and machinery needed to run Claude (and other agents)
  # unattended over SSH. The homelab dev container consumes it through its own
  # flake and layers cluster-specific tooling on top. Anything host-specific
  # (a particular cluster's CLIs, that cluster's Grafana MCP) belongs in the
  # consuming environment, not here.
  imports = [
    ./cli-tools.nix
    ./claude.nix
    ./remote-agent.nix
    ./shell-extras.nix
    ./sshd.nix
  ];
}
